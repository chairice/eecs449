#!/usr/bin/env bash
# Build all production pieces; stop a dev server sharing this checkout first.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
jac_bin="${JAC_BIN:-$repo_dir/scripts/jac}"
worker_python="${WORKER_PYTHON:-$repo_dir/workers/.venv/bin/python}"
expected="$(sed -n 's/^jac-version = "==\([^"]*\)"$/\1/p' "$repo_dir/web/jac.toml")"
actual="$("$jac_bin" --version)"
if [[ -z "$expected" || "$actual" != "jac $expected "* ]]; then
    printf 'The production build requires the pinned Jac compiler.\n' >&2
    exit 1
fi
if [[ ! -x "$worker_python" ]]; then
    "${PYTHON_BIN:-python3.13}" -m venv "$repo_dir/workers/.venv"
fi
"$worker_python" -m pip install -r "$repo_dir/workers/requirements.lock"
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-$repo_dir/workers/.browsers}"
"$worker_python" -m playwright install chromium
cd "$repo_dir/web"
"$jac_bin" install
"$jac_bin" build main.jac
"$worker_python" "$repo_dir/scripts/finalize-studio-build.py"
"$worker_python" "$repo_dir/scripts/check-build-secrets.py" "$repo_dir/web/dist/everyday-agent-web.jab"
