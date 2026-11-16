#!/usr/bin/env bash
# Run the native Jac app and its isolated research worker together.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
worker_python="$repo_dir/workers/.venv/bin/python"
if [[ ! -x "$worker_python" ]]; then
  printf 'Set up workers/.venv following workers/README.md first.\n' >&2
  exit 1
fi
exec "$worker_python" "$repo_dir/scripts/dev-studio.py"
