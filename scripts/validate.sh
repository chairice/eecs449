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
python3 "$repo_dir/scripts/finalize-studio-build.py"
python3 "$repo_dir/scripts/check-build-secrets.py" "$repo_dir/web/dist/everyday-agent-web.jab"
node --test "$repo_dir/scripts/test-client-theme.mjs" "$repo_dir/scripts/test-client-comparison.mjs" "$repo_dir/scripts/test-client-composer.mjs" "$repo_dir/scripts/test-client-atlas.mjs" "$repo_dir/scripts/test-client-atlas-navigation.mjs" "$repo_dir/scripts/test-client-atlas-flow.mjs" "$repo_dir/scripts/test-client-planning-states.mjs" "$repo_dir/scripts/test-client-studio.mjs" "$repo_dir/scripts/test-studio-offline.mjs" "$repo_dir/scripts/test-chat-markdown.mjs" "$repo_dir/scripts/test-studio-weather.mjs" "$repo_dir/scripts/test-studio-options.mjs"

node --test "$repo_dir/scripts/test-trip-pdf.mjs" "$repo_dir/scripts/test-studio-map.mjs" "$repo_dir/scripts/test-studio-agenda.mjs"

if [[ -x "$repo_dir/workers/.venv/bin/python" ]]; then
    cd "$repo_dir"
    workers/.venv/bin/python -m pytest -c workers/pyproject.toml workers/tests -q
    workers/.venv/bin/python scripts/test-research-browser.py
else
    printf 'Worker tests require workers/.venv; see workers/README.md.\n' >&2
    exit 1
fi
