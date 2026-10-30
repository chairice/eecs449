#!/usr/bin/env bash
# Run from any directory; always resolve Jac configuration from web/.
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir/web"

jac_bin="${JAC_BIN:-jac}"
expected_version="$(sed -n 's/^jac-version = "==\([^"]*\)"$/\1/p' jac.toml)"
actual_version="$("$jac_bin" --version)"
if [[ -z "$expected_version" || "$actual_version" != "jac $expected_version "* ]]; then
    printf 'Expected Jac %s; found: %s\nSee web/README.md for setup.\n' "$expected_version" "$actual_version" >&2
    exit 1
fi

"$jac_bin" check .
"$jac_bin" test -d tests/ -v
"$jac_bin" build main.jac
node --test "$repo_dir/scripts/test-client-comparison.mjs" "$repo_dir/scripts/test-client-composer.mjs" "$repo_dir/scripts/test-client-atlas.mjs"
