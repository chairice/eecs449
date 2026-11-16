# Detour planning runtime

Jac owns account access, accepted trips, atomic revision transactions, conversational decisions, Undo, deletion/recovery and revision history. This Python process runs Anthropic and an isolated Chromium research browser outside those transactions. It reads a private SQLite WAL work queue; it cannot directly mutate Jac's accepted trips. Routine requested edits commit immediately through Jac after validation; consequential assistant suggestions ask in the main chat and bind the answer to the pending decision and current revision. Fixed/booked commitments remain protected.

Public research supports source-backed flight, stay and car cards with strict active date/party/time evidence. The fresh-guest app pipeline produced nine real cards for the exact two-flight/San Francisco hotel scenario without itinerary edits; Airbnb produced three dated home/room offers. The full car-chat pipeline also passed with three genuine dated car cards and unchanged itinerary, starting from an observed public provider-results URL. The combined-main validation passed 74 Jac source checks, 134 Jac tests, 81 Node tests and 162 Python tests, the real Chromium date-picker/stale-reference regression, full client/JAB build, offline finalization and secret scan. Production-package tests and deployment evidence are recorded separately in the status document. See the status link below for the final outcomes.

NWS weather is independent auxiliary data: forecasts and official alerts refresh for relevant ground locations without editing the itinerary. Cached evidence is bounded and invalidated when dates/locations change; a forecast outage does not erase a retained official warning. Long-range trips use a quiet availability state. See [current implementation/evidence](../docs/trip-planner-implementation-status.md#current-detour-implementation).

## Local setup

```sh
python3.13 -m venv workers/.venv
workers/.venv/bin/python -m pip install -r workers/requirements.lock
PLAYWRIGHT_BROWSERS_PATH="$PWD/workers/.browsers" workers/.venv/bin/python -m playwright install chromium
cp workers/.env.example workers/.env
# Configure ANTHROPIC_API_KEY in workers/.env; keep this file private.
bash scripts/dev-studio.sh
```

Open `http://localhost:8000/` for the Detour landing page or `http://localhost:8000/studio` for the workspace. Jac's API runs on port 8001 in development. `PLANNER_MODEL` selects the Anthropic model; the default is `claude-sonnet-5-5`. No credential is sent to the browser.

Run deterministic tests from the repository root. The full validation includes a local Chromium interaction regression; install Chromium during setup above. These checks need no model key or public-site access:

```sh
workers/.venv/bin/python -m pytest -c workers/pyproject.toml workers/tests -q
JAC_BIN="$PWD/scripts/jac" bash scripts/validate.sh
```

Validation finalizes the studio's service worker in both the built client and the
Jac artifact. Jac 0.37.14's generic worker lacks the studio navigation fallback
and caches generic API responses, so use the repository validation command for
release builds. If invoking `jac build main.jac` directly from `web/`, follow it
with `python3 ../scripts/finalize-studio-build.py`. Stop the dev server before
building, then restart it: the compiler shares prepared-module caches.

The last loaded trip, including its accepted itinerary and imported booking
details, is cached on that device. Load the production app online once before
offline use. Signing out clears that account's device cache. Offline maps,
research, account synchronization and new edits are not supported. The
development Vite server does not install the production service worker.

## Live verification

These opt-in tests use the configured Anthropic credits. They create synthetic
test trips and do not change user trips or make bookings:

```sh
export PYTHONPATH="$PWD/workers:$PWD/web"
export PLAYWRIGHT_BROWSERS_PATH="$PWD/workers/.browsers"
workers/.venv/bin/python scripts/test-studio-live.py --scenario mixed
workers/.venv/bin/python scripts/test-studio-live.py --scenario business
workers/.venv/bin/python scripts/test-studio-live.py --scenario arizona
workers/.venv/bin/python scripts/test-studio-live.py --scenario day_order
workers/.venv/bin/python scripts/test-studio-import-live.py
workers/.venv/bin/python scripts/test-studio-edits-live.py --run-live
workers/.venv/bin/python scripts/test-studio-research-live.py combined
workers/.venv/bin/python scripts/test-studio-research-live.py airbnb
workers/.venv/bin/python scripts/test-studio-research-live.py car
```

Research acceptance requires real option coverage; generic search links alone fail. `combined` requires both DTW → SFO November 22 and SFO → XNA November 25, 2026 plus a San Francisco hotel November 22–25 for one adult/one room. `airbnb` and `car` exercise additional sources. Current combined and Airbnb live acceptance passed, as did the full fresh-guest flight/hotel app journey. The full car-chat pipeline also passed with three real cards, using a genuine observed provider-results URL as a research lead; broad unaided provider coverage remains best effort. Source access may change after a successful run.

`scripts/test-studio-api.py` exercises the actual running local Jac API with isolated synthetic accounts: authentication/ownership, hidden helper isolation, concurrent revisions, immediate edits, Undo, deletion/recovery and independent weather. No key is needed. Final execution passed against the latest rebuilt/restarted server, with the site returning HTTP 200 and worker ready; results are in `/tmp/detour-final-native-api.log`. Earlier universal-approval API results are historical. `scripts/preview-studio.py` serves the production client on port 8002
and proxies the existing local API for service-worker and offline QA; it is
not a production server.

## Production runtime

[The deployment guide](../deploy/README.md) describes `scripts/build-studio.sh`, the sealed production supervisor `scripts/serve-studio.py`, the combined health check and the selected free temporary HTTPS tunnel. Production starts the Jac server and one Chromium worker together, using an absolute private `DETOUR_STATE_DIR` for stable application materialization, PostgreSQL/graph storage, the queue/captures/uploads and a persisted signing key. The worker imports server helpers from that materialized release. Keep worker code and the sealed artifact from the same release checkout. The default production store is separate from development data.

`PLANNER_ENV_FILE` explicitly selects a private local environment file; otherwise supply `ANTHROPIC_API_KEY` in the host's private environment. Production binds to one public application port (8080 in the native deployment example); no worker port is exposed. Model calls still consume configured Anthropic credits even when hosting/tunneling is free.

## Resource and deployment boundary

The initial runtime is one host with one elected worker, a persistent private volume for `web/.jac/data/planner`, and Jac's persistent PostgreSQL store. Set `PLANNER_DATA_DIR` to relocate the private worker volume. Jobs are leased, cancellation invalidates late results, and expired leases are retried up to three attempts. Queue admission is bounded to four active tasks per owner and forty globally. Research is limited to 64 model rounds; source access is read-only and stops before login, booking, or payment. This is not a multi-host queue; do not deploy independent replicas against separate SQLite files.

Travel inventory is researched on public websites and presented as compact source cards in chat with a comparison view. Real observed starting, per-person, per-night, per-day and total prices are supported; a provider results/property page can serve as a handoff. Known wrong-date/wrong-party results are rejected. Public-source evidence retains excerpts, active search facts and provenance; it does not guarantee future prices or website access. Search links remain separate when no relevant option is found.

The canonical offer `price` contains `amountMinor`, `currency`, `basis` (`TOTAL`, `PER_PERSON`, `PER_NIGHT`, `PER_DAY`), `from`, `quantity`, `estimatedTotalMinor` and `feesIncluded`. Calculations are validated against the price basis and quantity. Starting/unit-derived estimates stay distinct from known total estimates and actual booking payments in budget summaries. Selecting an option never marks it booked. Historical `totalMinor`/mandatory-all-in-only rules are superseded. Captured pages are untrusted input. The research browser has no user profile, credentials, filesystem-upload tool, or arbitrary-code tool. Public URL and DNS guards exclude private network targets.

Map data: OpenStreetMap tiles are requested interactively with visible attribution, without bulk prefetch or offline tile caching. City/airport coordinates come from the existing GeoNames/OurAirports catalog; additional places use cached, throttled Photon queries. Set `PLANNER_GEOCODER_URL` for another compatible deployment. Ambiguous or unavailable coordinates remain unresolved. See [OSM tile policy](https://operations.osmfoundation.org/policies/tiles/) and [Photon](https://github.com/komoot/photon).
