#!/usr/bin/env bash
# Compatibility wrapper. The current optional Render blueprint builds Docker.
# For another host, install pinned Jac/Python first, then use this full build.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$repo_dir/scripts/build-studio.sh"
