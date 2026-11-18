#!/usr/bin/env python3
"""Supervise Jac and its worker with the same private runtime configuration."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(os.getenv("PLANNER_ENV_FILE", str(ROOT / "workers/.env")))
environment = dict(os.environ)
environment["PYTHONPATH"] = os.pathsep.join([str(ROOT / "workers"), str(ROOT / "web")])
environment["DETOUR_EMBEDDED_WORKER"] = "off"  # The worker runs as its own process below.
environment.setdefault("PLANNER_DATA_DIR", str(ROOT / "web/.jac/data/planner"))
environment.setdefault("PLAYWRIGHT_BROWSERS_PATH", str(ROOT / "workers/.browsers"))
children = []
stopping = False


def stop(*_):
    global stopping
    if stopping: return
    stopping = True
    for child in children:
        if child.poll() is None:
            try: os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError: pass


def main():
    signal.signal(signal.SIGTERM, stop); signal.signal(signal.SIGINT, stop)
    children.append(subprocess.Popen([sys.executable, "-m", "atlas_runtime"], cwd=ROOT, env=environment, start_new_session=True))
    children.append(subprocess.Popen([str(ROOT / "scripts/jac"), "run", "--dev", "main.jac"], cwd=ROOT / "web", env=environment, start_new_session=True))
    code = 0
    try:
        while not stopping:
            for child in children:
                if child.poll() is not None:
                    code = child.returncode or 1
                    stop()
                    break
            time.sleep(.3)
    finally:
        stop()
        for child in children:
            try: child.wait(timeout=8)
            except subprocess.TimeoutExpired:
                try: os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError: pass
    return code


if __name__ == "__main__": sys.exit(main())
