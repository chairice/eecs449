"""Run the planning worker on a thread inside the web server.

Hosts that start only the Jac app (such as JacHammer previews) have no separate
worker process, so Studio messages would stay "Queued" forever. The first job
enqueued starts this thread. It takes part in the same heartbeat election as a
separate worker, so it stands down when one is already running.
scripts/serve-studio.py and scripts/dev-studio.py run their own worker and set
DETOUR_EMBEDDED_WORKER=off.
"""
from __future__ import annotations

import logging
import os
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


def _load_runner():
    if not os.getenv("ANTHROPIC_API_KEY", "").strip():
        raise RuntimeError("ANTHROPIC_API_KEY is not set on this server.")
    workers = Path(__file__).resolve().parents[2] / "workers"
    if workers.is_dir() and str(workers) not in sys.path:
        sys.path.append(str(workers))
    from atlas_runtime.__main__ import run
    return run


def _main() -> None:
    from server import planning_jobs as jobs
    from server.planning_core import uid

    worker_id = uid("worker")
    for _ in range(16):
        if jobs.heartbeat(worker_id):
            break
        time.sleep(1)
    else:
        return  # A separate worker owns the queue.
    stopped = threading.Event()

    def beat():
        while not stopped.wait(4):
            if not jobs.heartbeat(worker_id):
                stopped.set()
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
            jobs.finish(job["id"], job["lease_token"], error=message[:300])
        else:
            stopped.wait(.6)
