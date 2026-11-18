"""Run the planning worker on a thread inside the web server.

Hosts that start only the Jac app (such as JacHammer previews) have no separate
worker process, so Studio messages would stay "Queued" forever. The first job
enqueued starts this thread. It takes part in the same heartbeat election as a
separate worker, so it stands down when one is already running.
scripts/serve-studio.py and scripts/dev-studio.py run their own worker and set
DETOUR_EMBEDDED_WORKER=off.
"""
from __future__ import annotations

import importlib
import importlib.util
import logging
import os
import shutil
import sqlite3
import subprocess
import sys
import threading
import time
from pathlib import Path

log = logging.getLogger("atlas.embedded")
_lock = threading.Lock()
_thread: threading.Thread | None = None


def enabled() -> bool:
    return os.getenv("DETOUR_EMBEDDED_WORKER", "on").strip().casefold() not in {"off", "0", "false", "no"}


def ensure_started() -> None:
    global _thread
    if not enabled():
        return
    with _lock:
        if _thread and _thread.is_alive():
            return
        _thread = threading.Thread(target=_main, name="detour-embedded-worker", daemon=True)
        _thread.start()


def env_files() -> list[Path]:
    root = Path(__file__).resolve().parents[1]
    return [root / ".env", root.parent / ".env"]


def load_project_env() -> None:
    """Fill unset variables from a project .env file.

    Jac's deploy tooling keeps secrets in the project's .env, but `jac run --serve`
    does not load it into the server, so a host that stores the key there would
    otherwise leave the process without it. Variables already set always win.
    """
    for path in env_files():
        try:
            lines = path.read_text().splitlines()
        except OSError:
            continue
        for line in lines:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            name, value = line.removeprefix("export ").split("=", 1)
            name, value = name.strip(), value.strip().strip("'\"")
            if name and value and not os.environ.get(name, "").strip():
                os.environ[name] = value


def _env_file_names(path: Path) -> list[str]:
    """Variable names in a .env file, marking empty ones. Never values."""
    names = []
    try:
        lines = path.read_text().splitlines()
    except OSError:
        return names
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.removeprefix("export ").split("=", 1)
        names.append(name.strip() + ("" if value.strip().strip("'\"") else " (empty)"))
    return names


def find_key() -> str:
    """The Anthropic key, under its usual name or any other a host chose.

    Anthropic keys start with "sk-ant-", so a variable holding one is recognized
    whatever it is called (e.g. a dashboard that stores secrets as API_KEY).
    """
    load_project_env()
    clean = lambda value: (value or "").strip().strip("'\"").strip()
    key = clean(os.getenv("ANTHROPIC_API_KEY"))
    if not key:
        key = next((clean(v) for v in os.environ.values() if clean(v).startswith("sk-ant-")), "")
    if key:
        os.environ["ANTHROPIC_API_KEY"] = key
    return key


def _missing_key_message() -> str:
    # Names only, never values, so the message is safe to show in the chat.
    similar = sorted(name for name in os.environ if "ANTHROPIC" in name.upper() or "API_KEY" in name.upper())
    files = [path.parent.name + "/.env [" + (", ".join(_env_file_names(path)) or "no variables") + "]"
             for path in env_files() if path.is_file()]
    return ("ANTHROPIC_API_KEY is not set on this server (similar variables: " + (", ".join(similar) or "none")
            + "; .env files: " + (", ".join(files) or "none") + "). Set it in the host's environment and restart.")


def _load_runner():
    # Hosting dashboards make it easy to paste a key with quotes or a trailing newline.
    key = find_key()
    if not key:
        raise RuntimeError(_missing_key_message())
    os.environ["ANTHROPIC_API_KEY"] = key
    # The Jac server resolves only modules its .jac files import; put the project root
    # (which holds atlas_runtime/) on the plain Python path for the worker package.
    root = Path(__file__).resolve().parents[1]
    if str(root) not in sys.path:
        sys.path.append(str(root))
    _ensure_libraries(root)
    from atlas_runtime.__main__ import run
    return run


WORKER_LIBRARIES = ["anthropic", "pydantic", "dotenv", "timezonefinder", "astral", "pypdf", "PIL", "playwright"]


def _missing_libraries() -> list[str]:
    importlib.invalidate_caches()
    return [name for name in WORKER_LIBRARIES if importlib.util.find_spec(name) is None]


def _ensure_libraries(root: Path) -> None:
    """Install jac.toml's [dependencies] once if the host started the app without them.

    `jac run --serve` builds the client but does not install Python dependencies, so a
    host that skips `jac install` would otherwise never have the worker's libraries.
    """
    for site in sorted(root.glob(".jac/venv/lib/python*/site-packages")):
        if str(site) not in sys.path:
            sys.path.append(str(site))
    if not _missing_libraries():
        return
    jac = os.getenv("JAC_BIN") or shutil.which("jac")
    if not jac:
        raise RuntimeError("its Python libraries are missing and the jac command was not found to install them.")
    log.warning("Installing the planning worker's Python libraries with 'jac install'")
    done = subprocess.run([jac, "install", "--no-npm"], cwd=root, capture_output=True, text=True, timeout=900)
    if done.returncode != 0:
        raise RuntimeError("'jac install' failed: " + (done.stderr or done.stdout).strip()[-300:])
    for site in sorted(root.glob(".jac/venv/lib/python*/site-packages")):
        if str(site) not in sys.path:
            sys.path.append(str(site))
    missing = _missing_libraries()
    if missing:
        raise RuntimeError("these Python libraries are still missing after 'jac install': " + ", ".join(missing))


def _main() -> None:
    from server import planning_jobs as jobs
    from server.planning_core import uid

    worker_id = uid("worker")
    for _ in range(16):
        try:
            if jobs.heartbeat(worker_id):
                break
        except sqlite3.OperationalError:  # e.g. "database is locked" while the store is first created
            log.warning("Embedded planning worker is waiting for the job store")
        time.sleep(1)
    else:
        return  # A separate worker owns the queue, or the store stayed unavailable.
    stopped = threading.Event()

    def beat():
        while not stopped.wait(4):
            try:
                if not jobs.heartbeat(worker_id):
                    stopped.set()
            except sqlite3.OperationalError:
                continue  # A busy store is retried; the 12-second lease outlasts one missed beat.
    threading.Thread(target=beat, name="detour-embedded-heartbeat", daemon=True).start()
    try:
        run = _load_runner()
    except Exception as exc:
        log.exception("Embedded planning worker could not start")
        _fail_queued(jobs, worker_id, stopped, f"The trip assistant can't run on this server: {exc}")
        return
    try:
        run(worker_id, stopped)
    finally:
        stopped.set()


def _fail_queued(jobs, worker_id: str, stopped: threading.Event, message: str) -> None:
    """Answer queued jobs with the startup error instead of leaving them queued."""
    while not stopped.is_set():
        job = jobs.claim(worker_id)
        if job:
            jobs.finish(job["id"], job["lease_token"], error=message[:600])
        else:
            stopped.wait(.6)
