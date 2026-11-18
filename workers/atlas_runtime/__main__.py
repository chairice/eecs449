"""Run with: workers/.venv/bin/python -m atlas_runtime (PYTHONPATH=workers:web)."""
import logging
import os
import signal
import threading
import time
from pathlib import Path

from dotenv import load_dotenv
from server import planning_jobs as jobs
from server.planning_core import uid

load_dotenv(Path(__file__).resolve().parents[2] / "workers/.env")
from .planner import plan
from .errors import public_error

log = logging.getLogger("atlas.worker")
stopped = threading.Event()


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    if not os.getenv("ANTHROPIC_API_KEY"):
        raise SystemExit("Configure ANTHROPIC_API_KEY in workers/.env before starting the planning worker.")
    worker_id = uid("worker")
    for attempt in range(16):
        if jobs.heartbeat(worker_id):
            break
        time.sleep(1)
    else:
        raise SystemExit("Another planning worker is already running for this data directory.")
    signal.signal(signal.SIGINT, lambda *_: stopped.set())
    signal.signal(signal.SIGTERM, lambda *_: stopped.set())

    def beat():
        while not stopped.wait(4):
            if not jobs.heartbeat(worker_id):
                stopped.set()
    threading.Thread(target=beat, daemon=True).start()
    run(worker_id, stopped)


def run(worker_id: str, stopped: threading.Event):
    """Claim and plan queued jobs until `stopped` is set.

    The caller owns the worker election and heartbeat. web/server/embedded_worker.py
    reuses this loop on a thread inside the web server.
    """
    log.info("Planning worker ready")
    while not stopped.is_set():
        job = jobs.claim(worker_id)
        if not job:
            stopped.wait(.6)
            continue
        job_id, token = job["id"], job["lease_token"]
        keepalive = threading.Event()

        def renew():
            while not keepalive.wait(20):
                if not jobs.renew(job_id, token):
                    return
        thread = threading.Thread(target=renew, daemon=True); thread.start()
        try:
            result = plan(job["request"], job["owner"], lambda message: jobs.progress(job_id, token, message),
                          lambda: not stopped.is_set() and jobs.still_running(job_id, token),
                          publish=lambda snapshot: jobs.preview(job_id, token, snapshot))
            jobs.finish(job_id, token, result=result)
            log.info("Completed task %s (%s source captures)", job_id, result.get("sourceCount", 0))
        except Exception as exc:
            # Provider exceptions may contain request context. Logs retain type only.
            message = public_error(exc)
            if stopped.is_set(): jobs.requeue(job_id, token)
            else: jobs.finish(job_id, token, error=message)
            log.warning("Task %s failed: %s", job_id, type(exc).__name__)
        finally:
            keepalive.set()


if __name__ == "__main__":
    main()
