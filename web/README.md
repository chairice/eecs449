# Detour web application

Detour is a conversational U.S. trip planner in Jac. `/` is the familiar landing page; planning entry points open `/studio`, with linked chat, map and itinerary views. Routine requested changes apply immediately with Undo. Consequential assistant suggestions ask a plain-language question in chat, bound to the current trip and pending decision. Fixed bookings and their referenced locations remain protected.

Start with the [repository README](../README.md), [worker guide](../workers/README.md) and [current implementation/evidence](../docs/trip-planner-implementation-status.md#current-detour-implementation). The [product contract](../docs/DETOUR-AGENT-HANDOFF.md) supersedes earlier Atlas branding, universal approval and all-in-price-only rules.

## Toolchain and first setup

Use **Jac 0.37.14**, pinned in `jac.toml`, **Python 3.13** for the worker, and **Node 22.11.0**, pinned in `../.nvmrc`, for JavaScript tooling. Jac's standalone compiler includes its Python/Bun/client runtime; do not install the retired `jaclang`/`jac-client` pip plugins into another environment.

Install the pinned compiler with the official installer:

```sh
curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh | bash -s -- --version 0.37.14
export PATH="$HOME/.local/bin:$PATH"
jac --version
```

Then follow the complete repository-root setup in [the README](../README.md#run-locally), including `jac install`, the locked worker dependencies, Chromium and private configuration. Initial dependency installation needs network access. Generated packages and bundles live in ignored `web/.jac/`; `jac.toml` is the npm dependency source of truth. Transitive npm dependencies are resolved on install and are not yet frozen in a tracked lockfile.

## Run the complete application

From the repository root:

```sh
bash scripts/dev-studio.sh
```

Open [the landing page](http://localhost:8000/) or [the studio](http://localhost:8000/studio). The supervisor starts Jac and the isolated research worker with the same private environment; the development API is on port 8001. Client edits hot-reload; server/worker changes require a coordinated restart. Use Ctrl+C to stop the supervisor.

Running `../scripts/jac run --dev main.jac` from `web/` starts only the Jac application. It does not replace the worker supervisor. Run Jac commands from `web/` so they use the pinned app configuration. The `../scripts/jac` wrapper verifies the compiler version and can recover a broken native launcher from its installed runtime.

## Validate and build

Stop the development supervisor before a release build: Jac shares prepared-module caches between development and sealing. From the repository root:

```sh
JAC_BIN="$PWD/scripts/jac" bash scripts/validate.sh
# Restart the app before this local API integration test:
workers/.venv/bin/python scripts/test-studio-api.py
```

Validation checks Jac sources, runs Jac tests, creates the complete production client and sealed `web/dist/everyday-agent-web.jab`, finalizes the offline worker in both outputs, verifies sealed payload hashes, scans for packaged secrets, and runs emitted-client, Python and real local Chromium regressions. The deterministic tests require no model key or public-source access; the Chromium binary must already be installed. Live model/source checks are separate opt-in commands in [the worker guide](../workers/README.md#live-verification).

The emitted client in `web/.jac/client/dist/` is only one part of the application. A static host alone cannot run accounts, graph persistence, planning jobs or browser research. For a direct build from `web/`, run `../scripts/jac build main.jac`, then `python3 ../scripts/finalize-studio-build.py` and the bundle secret scan before distributing the artifact. Restart development after building.

For local production-client/offline QA, `workers/.venv/bin/python scripts/preview-studio.py` serves the built client on port 8002 and proxies the already-running local Jac API. It is a test preview, not a production server.

## Current source map

Paths below are relative to `web/` unless shown otherwise.

| Path | Responsibility |
| --- | --- |
| `main.jac`, `pages/` | File-based routes, explicit endpoint imports and landing/studio shell selection |
| `components/TripStudio.jac`, `studio.css` | Conversation, progress/composer, focused workspace and responsive navigation |
| `components/StudioDetails.jac`, `StudioOffers.jac`, `StudioWeather.jac` | Compact type-specific details, real option cards and auxiliary weather |
| `components/ChatMarkdown.jac` | CommonMark/GFM with inert raw HTML, unsafe links and arbitrary images |
| `components/PlannerMap.jac` | Linked places and sourced road geometry; provisional connections remain distinct |
| `client/planning_state.jac`, `client/planning_rpc.jac` | Device cache, current DTO helpers and authenticated protected-endpoint bridge |
| `client/account.jac`, `components/AuthPanels.jac` | Existing Jac identity system and guest/account handoff |
| `server/planning.jac` | Account-owned trip/profile/revision graph, atomic writes and protected endpoints |
| `server/planning_core.py`, `server/planning_api.py` | Structural validation, source/selection/budget checks and worker-result staging |
| `server/planning_jobs.py`, `server/planning_lifecycle.py` | Private SQLite work queue, leases, recoverable deletion and draft lifecycle |
| `server/planning_weather.py` | Independent real NWS refresh/cache, stale-input binding and retained official alerts |
| `atlas_runtime/` | Anthropic interpretation, isolated public research browser and geographic tools |
| `offline-worker.js`, `../scripts/finalize-studio-build.py` | Saved-itinerary offline policy and sealed-artifact service-worker replacement |

## Storage and production boundary

Accounts and accepted trips live in Jac PostgreSQL. Guest work and the last loaded itinerary are cached on the device; an authenticated account provides server save/resume. Internal `Atlas` module/cache names are retained for compatibility and are not a second product. Signing out clears that account's device trip/preferences cache.

The worker queue, captures and uploads are private data under `web/.jac/data/planner` by default, or `PLANNER_DATA_DIR`. They must share persistent storage with the one worker using that queue. Keep secrets in ignored `workers/.env` for local development or the deployment platform's private secret store, outside Jac's packaged `web/` directory. Never commit runtime graph data, captures, uploads or credentials.

A production deployment needs the Jac server, a supervised Chromium-capable worker, private persistent worker storage, PostgreSQL and stable authentication configuration. Current deployment status is recorded in [implementation status](../docs/trip-planner-implementation-status.md#release-and-deployment-status); local test results alone do not establish public hosting.

## Production deployment

The current public [landing page](https://activity-fed-fame-sense.trycloudflare.com/) and [studio](https://activity-fed-fame-sense.trycloudflare.com/studio) run through a free temporary HTTPS tunnel to the Mac-hosted sealed production server. The public chat/worker/reply path was verified; the Mac, app and tunnel must remain available.

Use [the deployment guide](../deploy/README.md) for the sealed server/worker supervisor, persistent storage, health check and free temporary HTTPS tunnel. Production uses one origin/port for both the built client and API; it does not use the development bridge on port 8001. Jac's graph browser and API documentation are disabled in production. The native production store is separate from development data, and the sealed app is materialized at a stable path to preserve database identity across upgrades.

## Retained compatibility routes

The earlier commuter planner remains at `/commuter`, `/plan` and `/trips`; the earlier Atlas journal remains at `/atlas`. Their fixture inventory, browser-local trip keys and legacy weather DTOs are separate from Detour's current studio. The [historical web reference](README-legacy.md) preserves their implementation details and the [legacy repository README](../docs/commuter-readme-legacy.md) preserves the earlier project description.
