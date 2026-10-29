#!/usr/bin/env bash
# Render start step: serve the built app on Render's $PORT on all interfaces.
# jac run stops when stdin closes, so stdin is held open on /dev/null.
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
jac_bin="${JAC_BIN:-$repo_dir/.render/bin/jac}"

cd "$repo_dir/web"
exec "$jac_bin" run --host 0.0.0.0 --port "${PORT:-10000}" main.jac < /dev/null
