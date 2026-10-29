#!/usr/bin/env bash
# Render start step: serve the sealed bundle the build made (no compile at
# start, so the port opens in seconds even on a small instance) on Render's
# $PORT. JAC_SERVE_HOST makes it listen on all interfaces; the bundle otherwise
# keeps jac.toml's 127.0.0.1. jac run stops when stdin closes, so stdin is held
# open on /dev/null.
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
jac_bin="${JAC_BIN:-$repo_dir/.render/bin/jac}"

cd "$repo_dir/web"
export JAC_SERVE_HOST="${JAC_SERVE_HOST:-0.0.0.0}"
exec "$jac_bin" run --host 0.0.0.0 --port "${PORT:-10000}" dist/everyday-agent-web.jab < /dev/null
