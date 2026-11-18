#!/usr/bin/env python3
"""Serve the sealed Detour app and its research worker on one persistent host.

Configuration values and credentials are never printed. A development .env is
loaded only when its path is explicitly supplied with PLANNER_ENV_FILE.
"""
from __future__ import annotations

import os
from pathlib import Path
import hashlib
import shutil
import secrets
import signal
import subprocess
import sys
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def materialize_release(bundle: Path, state: Path) -> Path:
    """Keep Jac's project identity stable across artifact upgrades.

    Jac's default .jab runner extracts into a content-hash directory. Embedded
    database names include the project directory, so that default would hide
    existing accounts after every new release. This directory is private code,
    never user state; graph/queue/uploads live in separate configured paths.
    """
    target = state / "app"
    marker = target / ".detour-release-sha256"
    previous = state / ".previous-app"
    if not target.exists() and (previous / ".detour-release-sha256").is_file():
        previous.rename(target)
    digest = hashlib.sha256(bundle.read_bytes()).hexdigest()
    if marker.is_file() and marker.read_text() == digest:
        return target
    if target.exists() and not marker.is_file():
        raise ValueError("The production app directory is not a managed release; choose a separate state directory.")
    temporary = Path(tempfile.mkdtemp(prefix=".release-", dir=state))
    try:
        with tarfile.open(bundle, "r:*") as archive:
            archive.extractall(temporary, filter="data")
        for required in ["main.jac", "jac.toml", ".jac/serve_manifest.json", ".jac/client/dist/index.html"]:
            if not (temporary / required).is_file():
                raise ValueError("The release is missing its sealed server or complete production client.")
        (temporary / ".detour-release-sha256").write_text(digest)
        if previous.exists():
            if not (previous / ".detour-release-sha256").is_file():
                raise ValueError("An unmanaged previous-release directory exists; preserve it before continuing.")
            shutil.rmtree(previous)
        if target.exists():
            target.rename(previous)
        temporary.rename(target)
        if previous.exists():
            shutil.rmtree(previous)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    return target


def private_directory(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.chmod(0o700)
    return path


def signing_secret(directory: Path) -> str:
    """Persist a single-host signing key without sending it to build output."""
    path = directory / "jwt-secret"
    if not path.exists():
        try:
            descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        except FileExistsError:
            pass
        else:
            with os.fdopen(descriptor, "w") as handle:
                handle.write(secrets.token_urlsafe(64))
    path.chmod(0o600)
    value = path.read_text().strip()
    if len(value) < 32:
        raise ValueError("The private signing-key file is invalid; restore its original value.")
    return value


def configuration(source: dict[str, str]) -> tuple[dict[str, str], list[str], list[str]]:
    environment = dict(source)
    if environment.get("PLANNER_ENV_FILE"):
        from dotenv import dotenv_values
        path = Path(environment["PLANNER_ENV_FILE"]).expanduser()
        if not path.is_file():
            raise ValueError("PLANNER_ENV_FILE does not point to an available private file.")
        for key, value in dotenv_values(path).items():
            if value is not None:
                environment.setdefault(key, value)
    if not environment.get("ANTHROPIC_API_KEY", "").strip():
        raise ValueError("Set ANTHROPIC_API_KEY in the host's private environment before starting Detour.")
    raw_state = environment.get("DETOUR_STATE_DIR", "")
    state = Path(raw_state).expanduser()
    if not raw_state or not state.is_absolute():
        raise ValueError("Set DETOUR_STATE_DIR to an absolute directory on durable private storage.")
    # In particular, never create runtime data inside the directory Jac seals.
    state = state.resolve()
    if state == ROOT / "web" or ROOT / "web" in state.parents:
        raise ValueError("DETOUR_STATE_DIR must be outside the packaged web directory.")
    private_directory(state)
    for key, name in [("PLANNER_DATA_DIR", "planner"), ("JAC_DATA_PATH", "graph"), ("JAC_CACHE_HOME", "jac-cache")]:
        environment.setdefault(key, str(state / name))
        private = Path(environment[key]).expanduser()
        if not private.is_absolute() or private.resolve() == ROOT / "web" or ROOT / "web" in private.resolve().parents:
            raise ValueError(f"{key} must be an absolute private path outside the packaged web directory.")
        private_directory(private)
    if not environment.get("JAC_SERVE_AUTH_SECRET"):
        environment["JAC_SERVE_AUTH_SECRET"] = signing_secret(state)
    elif len(environment["JAC_SERVE_AUTH_SECRET"]) < 32:
        raise ValueError("JAC_SERVE_AUTH_SECRET must contain at least 32 characters.")
    environment.update(JAC_SERVE_HOST="0.0.0.0", JAC_SERVE_WORKERS="1", JAC_SERVE_DOCS="false", JAC_SERVE_GRAPH="false",
                       DETOUR_EMBEDDED_WORKER="off")  # This supervisor runs the worker as its own process.
    environment["PYTHONPATH"] = os.pathsep.join([str(ROOT / "workers"), str(state / "app")])
    environment.setdefault("PLAYWRIGHT_BROWSERS_PATH", str(ROOT / "workers/.browsers"))
    if not environment.get("JAC_DB_URL"):
        # This supervisor deliberately runs one host and one SQLite queue. An
        # incidental Kubernetes env var must not change that storage topology.
        environment.pop("KUBERNETES_SERVICE_HOST", None)
        environment.pop("KUBERNETES_SERVICE_PORT", None)
    try:
        port = int(environment.get("PORT", "8000"))
        if not 1 <= port <= 65535:
            raise ValueError()
    except ValueError:
        raise ValueError("PORT must be an integer between 1 and 65535.") from None
    python = Path(environment.get("WORKER_PYTHON", str(ROOT / "workers/.venv/bin/python")))
    jac = Path(environment.get("JAC_BIN", str(ROOT / "scripts/jac")))
    bundle = Path(environment.get("DETOUR_BUNDLE", str(ROOT / "web/dist/everyday-agent-web.jab"))).expanduser().resolve()
    if not python.is_file() or not os.access(python, os.X_OK):
        raise ValueError("Install the worker runtime or set WORKER_PYTHON to its Python executable.")
    if not jac.is_file() or not os.access(jac, os.X_OK):
        raise ValueError("Install the pinned compiler or set JAC_BIN to its executable.")
    if not bundle.is_file():
        raise ValueError("Build the complete release before starting the production supervisor.")
    environment["DETOUR_BUNDLE"] = str(bundle)
    return environment, [str(python), "-m", "atlas_runtime"], [str(jac), "run", "--no-dev", "--host", "0.0.0.0", "--port", str(port), str(state / "app/main.jac")]


def main() -> int:
    try:
        environment, worker_command, web_command = configuration(dict(os.environ))
        import fcntl
        state = Path(environment["DETOUR_STATE_DIR"]).expanduser().resolve()
        lock = (state / ".supervisor.lock").open("a")
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            lock.close()
            raise ValueError("Another Detour production supervisor is already using this state directory.") from None
        app = materialize_release(Path(environment["DETOUR_BUNDLE"]), state)
    except tarfile.TarError:
        print("The sealed release is not a safe, readable Jac archive.", file=sys.stderr)
        return 2
    except (ValueError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 2
    children: list[subprocess.Popen] = []
    stopping = False

    def stop(*_):
        nonlocal stopping
        if stopping:
            return
        stopping = True
        for child in children:
            if child.poll() is None:
                try:
                    os.killpg(child.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    code = 0
    try:
        for command, cwd in [(worker_command, ROOT), (web_command, app)]:
            children.append(subprocess.Popen(command, cwd=cwd, env=environment, stdin=subprocess.DEVNULL, start_new_session=True))
        print("Detour production app and research worker starting; private state retained on the configured volume.", flush=True)
        while not stopping:
            for child in children:
                if child.poll() is not None:
                    code = child.returncode or 1
                    stop()
                    break
            time.sleep(.3)
    except OSError:
        print("Could not launch a required Detour process. Check the configured executable paths.", file=sys.stderr)
        code = 1
    finally:
        stop()
        for child in children:
            try:
                child.wait(timeout=12)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                child.wait()
        lock.close()
    return code


if __name__ == "__main__":
    raise SystemExit(main())
