import os

# Tests drive the queue directly; never let enqueue() start the web server's
# embedded worker thread (web/server/embedded_worker.py) against a test store.
os.environ["DETOUR_EMBEDDED_WORKER"] = "off"
