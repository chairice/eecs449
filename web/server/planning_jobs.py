"""Private durable worker ledger behind owner-authorized Jac endpoints.

Canonical trips/revisions live in Jac's user graph. This bounded single-host
queue is a worker resource, persisted alongside private attachments/evidence.
It never writes accepted trip state. A durable volume is required in deployment.
"""
from __future__ import annotations

import base64
import hashlib
import os
import secrets
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path

from server.planning_core import PlanningError, dumps, fingerprint, identifier, loads, now, record, sequence, text, uid, validate_trip


def data_dir() -> Path:
    path = Path(os.environ.get("PLANNER_DATA_DIR", str(Path(__file__).resolve().parents[1] / ".jac/data/planner")))
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    return path


@contextmanager
def connection():
    db = sqlite3.connect(data_dir() / "runtime.sqlite3", timeout=15)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA busy_timeout=15000")
    db.executescript("""
      CREATE TABLE IF NOT EXISTS jobs (
        id TEXT PRIMARY KEY, owner TEXT NOT NULL, turn_key TEXT NOT NULL,
        kind TEXT NOT NULL, status TEXT NOT NULL, request TEXT NOT NULL,
        request_hash TEXT NOT NULL, result TEXT NOT NULL DEFAULT '{}',
        error TEXT NOT NULL DEFAULT '', progress TEXT NOT NULL DEFAULT 'Queued',
        created REAL NOT NULL, updated REAL NOT NULL, lease_until REAL NOT NULL DEFAULT 0,
        lease_token TEXT NOT NULL DEFAULT '', attempts INTEGER NOT NULL DEFAULT 0,
        UNIQUE(owner, turn_key));
      CREATE INDEX IF NOT EXISTS jobs_pending ON jobs(status, created);
      CREATE TABLE IF NOT EXISTS attachments (
        id TEXT PRIMARY KEY, owner TEXT NOT NULL, name TEXT NOT NULL,
        media TEXT NOT NULL, size INTEGER NOT NULL, path TEXT NOT NULL, created REAL NOT NULL);
      CREATE TABLE IF NOT EXISTS claims (guest TEXT PRIMARY KEY, owner TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS runtime (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated REAL NOT NULL);
    """)
    try:
        yield db
        db.commit()
    except BaseException:
        db.rollback()
        raise
    finally:
        db.close()


def guest_owner(token: str) -> str:
    if not isinstance(token, str) or len(token) < 40 or len(token) > 160 or not token.isascii() or not all(c.isalnum() or c in "-_" for c in token):
        raise PlanningError("This guest session is invalid. Your saved draft is still on this device.")
    return "guest:" + hashlib.sha256(token.encode()).hexdigest()


def account_owner(root_id: str) -> str:
    return "account:" + identifier(root_id, "account root")


def validated_request(raw: str) -> dict:
    value = record(loads(raw), "planning request")
    request = {
        "tripId": identifier(value.get("tripId"), "trip ID"),
        "baseRevision": value.get("baseRevision", 0),
        "snapshot": validate_trip(value.get("snapshot")),
        "message": text(value.get("message"), "message", 160000, empty=False),
        "clientTurnId": identifier(value.get("clientTurnId"), "turn ID"),
        "workingContext": record(value.get("workingContext", {}), "working context"),
        "conversation": sequence(value.get("conversation", []), "conversation", 1500),
        "summary": text(value.get("summary", ""), "conversation summary", 20000),
        "contextRefs": sequence(value.get("contextRefs", []), "selected context", 20),
        "attachments": sequence(value.get("attachments", []), "attachments", 8),
        "today": text(value.get("today", ""), "current date", 10),
        "timeZone": text(value.get("timeZone", "America/Detroit"), "current time zone", 100),
        "preferences": record(value.get("preferences", {}), "preferences"),
        "profileVersion": value.get("profileVersion", 0),
        "researchQuery": value.get("researchQuery"),
        "researchContext": record(value.get("researchContext", {}), "research context"),
        "proposal": value.get("proposal"),
    }
    if type(request["baseRevision"]) is not int or request["baseRevision"] < 0:
        raise PlanningError("Invalid trip revision.")
    if request["snapshot"]["id"] != request["tripId"]:
        raise PlanningError("The request belongs to a different trip.")
    for turn in request["conversation"]:
        record(turn, "conversation turn")
        if turn.get("role") not in {"user", "assistant"}:
            raise PlanningError("Invalid conversation role.")
        text(turn.get("content", ""), "conversation message", 160000)
    if len(dumps(request).encode()) > 1_500_000:
        raise PlanningError("Please import this material as separate attachments.")
    return request


def _wake_worker() -> None:
    from server.embedded_worker import ensure_started
    ensure_started()


def enqueue(owner: str, request_json: str, *, deferred: bool = False, kind: str = "PLAN") -> str:
    _wake_worker()
    request = validated_request(request_json)
    digest = fingerprint(request)
    with connection() as db:
        db.execute("BEGIN IMMEDIATE")
        existing = db.execute("SELECT * FROM jobs WHERE owner=? AND turn_key=?", (owner, request["clientTurnId"])).fetchone()
        if existing:
            if existing["request_hash"] != digest:
                raise PlanningError("This message ID was already used for a different request.")
            return existing["id"]
        active = db.execute("SELECT COUNT(*) FROM jobs WHERE owner=? AND status IN ('PREPARED','QUEUED','RUNNING')", (owner,)).fetchone()[0]
        if active >= 4:
            raise PlanningError("Please wait for or stop an existing research task before starting another.")
        if db.execute("SELECT COUNT(*) FROM jobs WHERE status IN ('PREPARED','QUEUED','RUNNING')").fetchone()[0] >= 40:
            raise PlanningError("Planning is busy. Your draft is kept; please try again shortly.")
        for attachment_id in request["attachments"]:
            if not db.execute("SELECT 1 FROM attachments WHERE id=? AND owner=?", (attachment_id, owner)).fetchone():
                raise PlanningError("An attachment is missing or belongs to another session.")
        job_id = uid("job"); stamp = time.time()
        db.execute("INSERT INTO jobs(id,owner,turn_key,kind,status,request,request_hash,created,updated) VALUES(?,?,?,?,?,?,?,?,?)",
                   (job_id, owner, request["clientTurnId"], kind, "PREPARED" if deferred else "QUEUED", dumps(request), digest, stamp, stamp))
        return job_id


def activate(owner: str, job_id: str) -> None:
    _wake_worker()
    with connection() as db:
        db.execute("UPDATE jobs SET status='QUEUED',updated=? WHERE id=? AND owner=? AND status='PREPARED'", (time.time(), job_id, owner))


def claim(worker_id: str, lease_seconds: float = 300) -> dict | None:
    with connection() as db:
        db.execute("BEGIN IMMEDIATE")
        stamp = time.time()
        db.execute("UPDATE jobs SET status='FAILED',error='This task was interrupted before it could start. Please resend the message.',updated=? WHERE status='PREPARED' AND created<?", (stamp, stamp - 600))
        db.execute("UPDATE jobs SET status='FAILED',error='The research task could not be resumed. Please retry.',updated=? WHERE status='RUNNING' AND lease_until<? AND attempts>=3", (stamp, stamp))
        row = db.execute("SELECT * FROM jobs WHERE (status='QUEUED' OR (status='RUNNING' AND lease_until<?)) AND attempts<3 ORDER BY created LIMIT 1", (stamp,)).fetchone()
        if not row:
            return None
        token = secrets.token_hex(24)
        db.execute("UPDATE jobs SET status='RUNNING',lease_until=?,lease_token=?,attempts=attempts+1,updated=?,progress='Understanding your request' WHERE id=?",
                   (stamp + lease_seconds, token, stamp, row["id"]))
        result = dict(row)
        result.update(lease_token=token, worker_id=worker_id, request=loads(row["request"]))
        return result


def progress(job_id: str, token: str, message: str) -> bool:
    with connection() as db:
        updated = db.execute("UPDATE jobs SET progress=?,updated=?,lease_until=? WHERE id=? AND lease_token=? AND status='RUNNING'",
                             (text(message, "progress", 300), time.time(), time.time() + 300, job_id, token)).rowcount
        return bool(updated)


def renew(job_id: str, token: str) -> bool:
    """Renew a lease without replacing the actual current research activity."""
    with connection() as db:
        return bool(db.execute("UPDATE jobs SET updated=?,lease_until=? WHERE id=? AND lease_token=? AND status='RUNNING'",
                               (time.time(), time.time() + 300, job_id, token)).rowcount)


def still_running(job_id: str, token: str) -> bool:
    with connection() as db:
        return bool(db.execute("SELECT 1 FROM jobs WHERE id=? AND lease_token=? AND status='RUNNING'", (job_id, token)).fetchone())


def preview(job_id: str, token: str, snapshot: dict) -> bool:
    """Publish only a structurally valid, unapproved working preview."""
    value = validate_trip(snapshot)
    with connection() as db:
        return bool(db.execute("UPDATE jobs SET result=?,updated=? WHERE id=? AND lease_token=? AND status='RUNNING'",
            (dumps({"preview": value}), time.time(), job_id, token)).rowcount)


def finish(job_id: str, token: str, result: dict | None = None, error: str = "") -> bool:
    with connection() as db:
        return bool(db.execute("UPDATE jobs SET status=?,result=?,error=?,progress=?,updated=?,lease_until=0 WHERE id=? AND lease_token=? AND status='RUNNING'",
                               ("FAILED" if error else "SUCCEEDED", dumps(result or {}), text(error, "error", 2000), "Needs attention" if error else "Ready", time.time(), job_id, token)).rowcount)


def requeue(job_id: str, token: str) -> bool:
    with connection() as db:
        return bool(db.execute("UPDATE jobs SET status='QUEUED',progress='Resuming after restart',lease_until=0,lease_token='',updated=? WHERE id=? AND lease_token=? AND status='RUNNING'",
                               (time.time(), job_id, token)).rowcount)


def read(owner: str, job_id: str, *, include_request: bool = False) -> dict:
    with connection() as db:
        row = db.execute("SELECT * FROM jobs WHERE id=? AND owner=?", (job_id, owner)).fetchone()
        if row is None:
            raise PlanningError("This planning task is unavailable.")
        result = {"id": row["id"], "kind": row["kind"], "status": row["status"], "progress": row["progress"],
                  "error": row["error"], "createdAt": row["created"], "updatedAt": row["updated"], "result": loads(row["result"])}
        if include_request:
            result["request"] = loads(row["request"])
        return result


def cancel(owner: str, job_id: str) -> dict:
    with connection() as db:
        if not db.execute("SELECT 1 FROM jobs WHERE id=? AND owner=?", (job_id, owner)).fetchone():
            raise PlanningError("This planning task is unavailable.")
        db.execute("UPDATE jobs SET status='CANCELLED',progress='Stopped',updated=? WHERE id=? AND owner=? AND status IN ('PREPARED','QUEUED','RUNNING')", (time.time(), job_id, owner))
    return read(owner, job_id)


def attachment(owner: str, filename: str, media: str, content_b64: str) -> dict:
    """Store bounded private upload bytes; filenames never become filesystem paths."""
    if media not in {"application/pdf", "image/png", "image/jpeg", "image/webp", "text/plain"}:
        raise PlanningError("Upload a PDF, image, or plain-text file.")
    if not isinstance(content_b64, str) or len(content_b64) > 14_000_000:
        raise PlanningError("Please keep each upload below 10 MB.")
    try:
        data = base64.b64decode(content_b64, validate=True)
    except ValueError as exc:
        raise PlanningError("The uploaded file could not be read.") from exc
    if not data or len(data) > 10_000_000:
        raise PlanningError("Please upload a nonempty file below 10 MB.")
    signatures = {"application/pdf": b"%PDF", "image/png": b"\x89PNG", "image/jpeg": b"\xff\xd8", "image/webp": b"RIFF"}
    if media in signatures and not data.startswith(signatures[media]):
        raise PlanningError("The file contents do not match its format.")
    if media == "text/plain":
        try:
            data.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise PlanningError("Please use a UTF-8 text file.") from exc
    item_id = uid("attachment")
    name = text(Path(filename).name, "filename", 240, empty=False)
    folder = data_dir() / "uploads"; folder.mkdir(exist_ok=True, mode=0o700)
    path = folder / item_id
    try:
        with connection() as db:
            db.execute("BEGIN IMMEDIATE")
            used = db.execute("SELECT COALESCE(SUM(size),0) FROM attachments WHERE owner=?", (owner,)).fetchone()[0]
            total = db.execute("SELECT COALESCE(SUM(size),0) FROM attachments").fetchone()[0]
            if used + len(data) > int(os.getenv("PLANNER_UPLOAD_OWNER_BYTES", "100000000")) or total + len(data) > int(os.getenv("PLANNER_UPLOAD_TOTAL_BYTES", "1000000000")):
                raise PlanningError("Attachment storage is full. Your existing documents and trip are kept; try pasting the relevant text instead.")
            descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            with os.fdopen(descriptor, "wb") as handle:
                handle.write(data)
            db.execute("INSERT INTO attachments VALUES(?,?,?,?,?,?,?)", (item_id, owner, name, media, len(data), str(path), time.time()))
    except BaseException:
        path.unlink(missing_ok=True)
        raise
    return {"id": item_id, "name": name, "media": media, "size": len(data)}


def attachments_for(owner: str, attachment_ids: list[str]) -> list[dict]:
    result = []
    with connection() as db:
        for item_id in attachment_ids:
            row = db.execute("SELECT * FROM attachments WHERE id=? AND owner=?", (item_id, owner)).fetchone()
            if row is None:
                raise PlanningError("An attachment is missing or belongs to another session.")
            result.append(dict(row))
    return result


def claim_guest(token: str, owner: str) -> None:
    guest = guest_owner(token)
    with connection() as db:
        db.execute("BEGIN IMMEDIATE")
        previous = db.execute("SELECT owner FROM claims WHERE guest=?", (guest,)).fetchone()
        if previous and previous["owner"] != owner:
            raise PlanningError("This guest work has already been saved to a different account.")
        db.execute("INSERT OR IGNORE INTO claims VALUES(?,?)", (guest, owner))
        db.execute("UPDATE jobs SET owner=? WHERE owner=?", (owner, guest))
        db.execute("UPDATE attachments SET owner=? WHERE owner=?", (owner, guest))


def assert_claimable(token: str, owner: str) -> None:
    with connection() as db:
        previous = db.execute("SELECT owner FROM claims WHERE guest=?", (guest_owner(token),)).fetchone()
        if previous and previous["owner"] != owner:
            raise PlanningError("This guest session has already been saved to another account. Start a new guest session to keep accounts separate.")


def heartbeat(worker_id: str) -> bool:
    """Elect one local worker; an expired heartbeat allows restart recovery."""
    with connection() as db:
        db.execute("BEGIN IMMEDIATE")
        row = db.execute("SELECT * FROM runtime WHERE key='worker' ").fetchone()
        if row and row["value"] != worker_id and row["updated"] > time.time() - 12:
            return False
        db.execute("INSERT INTO runtime VALUES('worker',?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value,updated=excluded.updated", (worker_id, time.time()))
        return True


def status() -> dict:
    with connection() as db:
        row = db.execute("SELECT updated FROM runtime WHERE key='worker'").fetchone()
    return {"workerReady": bool(row and row["updated"] > time.time() - 15)}


def enqueue_json(owner: str, request_json: str, deferred: bool = False) -> str:
    return enqueue(owner, request_json, deferred=deferred)


def read_json(owner: str, job_id: str) -> str:
    return dumps(read(owner, job_id))


def result_json(owner: str, job_id: str) -> str:
    job = read(owner, job_id, include_request=True)
    if job["status"] != "SUCCEEDED":
        raise PlanningError("This planning task has not finished yet.")
    return dumps(job)
