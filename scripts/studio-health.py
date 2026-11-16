#!/usr/bin/env python3
"""Check both the production web process and its independent worker."""
import json
import os
import sys
from urllib.request import Request, urlopen


def main():
    base = "http://127.0.0.1:" + os.environ.get("PORT", "8000")
    try:
        with urlopen(base + "/healthz", timeout=5) as response:
            if response.status != 200:
                return 1
        request = Request(base + "/function/planner_status", data=b"{}", headers={"Content-Type": "application/json"})
        with urlopen(request, timeout=5) as response:
            result = json.load(response)["data"]["result"]
            status = json.loads(result) if isinstance(result, str) else result
            return 0 if status.get("workerReady") else 1
    except (OSError, ValueError, KeyError, TypeError):
        return 1


if __name__ == "__main__":
    sys.exit(main())
