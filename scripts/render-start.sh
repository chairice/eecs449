#!/usr/bin/env bash
# Compatibility wrapper: the current app requires BOTH Jac and its worker.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
exec "${WORKER_PYTHON:-$repo_dir/workers/.venv/bin/python}" "$repo_dir/scripts/serve-studio.py"
