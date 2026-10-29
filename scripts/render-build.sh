#!/usr/bin/env bash
# Render build step: install the pinned Jac compiler inside the repository (only
# the checkout survives from build to runtime), then install dependencies and
# build the production client. Locally, set JAC_BIN to use an existing jac.
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(sed -n 's/^jac-version = "==\([^"]*\)"$/\1/p' "$repo_dir/web/jac.toml")"
jac_bin="${JAC_BIN:-$repo_dir/.render/bin/jac}"

if [[ ! -x "$jac_bin" ]]; then
    # The official installer always writes to ~/.local/bin; copy it into the repo.
    curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh | bash -s -- --version "$version"
    mkdir -p "$(dirname -- "$jac_bin")"
    cp "$HOME/.local/bin/jac" "$jac_bin"
fi
"$jac_bin" --version

cd "$repo_dir/web"
"$jac_bin" install
"$jac_bin" build main.jac
