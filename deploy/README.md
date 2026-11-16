# Deploy Detour

Detour runs a sealed Jac application and a separate Anthropic/Chromium research worker on one host. Both use private persistent storage. A static client upload does not provide account storage, trip planning or research.

<!-- PUBLIC_DEPLOYMENT_STATUS -->
**Public app: [https://activity-fed-fame-sense.trycloudflare.com/](https://activity-fed-fame-sense.trycloudflare.com/)** · [Studio](https://activity-fed-fame-sense.trycloudflare.com/studio)

The feature and integrated teammate changes were merged to remote `main` at [`78baaf7`](https://github.com/chairice/eecs449/commit/78baaf7063be403f9f8f4ed0f36a2ec8ffd34767) before deployment. The production package was committed and published at [`9abd340`](https://github.com/chairice/eecs449/commit/9abd340). Public HTTPS home/studio and the same-origin chat → queue → Anthropic → staged/rendered reply journey passed in a real browser. This is a free temporary public self-hosted deployment; its availability depends on the Mac and tunnel below.

Native production checks passed for worker health, authentication/ownership, concurrent revisions, Undo, deletion/recovery and weather. Stable signing/session state, login and an exact saved trip survived a different-artifact upgrade and restoration of the original artifact. The final Python suite passed **167 tests**. Detailed local evidence paths are in [implementation status](../docs/trip-planner-implementation-status.md#release-and-deployment-status).

## Free deployment selected for this release

The free path is self-hosted on the existing Mac: sealed production app, research worker and persistent PostgreSQL/worker data, exposed over HTTPS through a [Cloudflare Quick Tunnel](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/). The tunnel needs no purchased domain or hosting subscription. Anthropic requests still consume the host's configured model credits.

This is a temporary public self-hosted demo, not an always-on managed cloud service. The Mac, production supervisor, tunnel process and network connection must remain available. The random `trycloudflare.com` hostname changes when the tunnel is recreated. Quick Tunnels have no SLA, support up to 200 in-flight requests and do not support Server-Sent Events; Detour's job-progress interface uses RPC polling. See [Cloudflare's published limits](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/).

JacHammer was investigated first. Its [Free plan](https://docs.jachammer.ai/introduction/plans-billing) provides a sandbox; permanent deployments require a paid plan. Current [sandbox documentation](https://docs.jachammer.ai/features/sandbox-vs-permanent-deploys) describes automatic sandbox expiry. Running this app's separate Chromium worker and persistent private queue there was not verified. The self-hosted path runs the complete application within the requested free-hosting constraint.

## Build the complete production release

Install the pinned toolchain and dependencies using [the repository setup](../README.md#run-locally). Stop a development supervisor sharing this checkout before building because Jac shares prepared-module caches.

From the repository root:

```sh
bash scripts/build-studio.sh
```

This installs the locked worker dependencies and Chromium, installs the Jac project dependencies, builds the complete `web/dist/everyday-agent-web.jab`, finalizes the production offline worker, updates and verifies the sealed manifest payload hashes, and scans the artifact for packaged secrets. It does not replace the full [validation command](../README.md#validate-and-preview), which also runs source checks and regression suites. Keep production code and the artifact from the same release checkout.

## Start the sealed app and worker

From the repository root:

```sh
DETOUR_STATE_DIR="$PWD/.detour-production" PLANNER_ENV_FILE="$PWD/workers/.env" PORT=8080 workers/.venv/bin/python scripts/serve-studio.py
```

The local production URL is `http://127.0.0.1:8080/`; `/studio` opens the workspace. Production serves the client and API on this single port. It does not use Vite, HMR or the development API on port 8001. The supervisor binds the app to `0.0.0.0`, starts one worker, and stops its paired process if either required child fails. Stop with Ctrl+C or send SIGTERM to the supervisor.

The private environment file is optional when `ANTHROPIC_API_KEY` is already present in the host environment. Production loads a file only when `PLANNER_ENV_FILE` is explicitly set. Keep that file outside the packaged `web/` directory. The default production store is separate from development data; this command does not copy development users, trips or private captures into the public instance.

Check both processes from another terminal:

```sh
PORT=8080 workers/.venv/bin/python scripts/studio-health.py
```

The command succeeds only when the web health endpoint responds and the worker reports ready. Production disables Jac's graph browser and API documentation. The native account, ownership and revision tests remain available via `scripts/test-studio-api.py`, with `ATLAS_TEST_API=http://127.0.0.1:8080` for the production port; they create isolated local test records.

## Start the free HTTPS tunnel

Install `cloudflared` following [Cloudflare's official download instructions](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/), then run it in a second terminal:

```sh
caffeinate -i cloudflared tunnel --url http://127.0.0.1:8080
```

The current Mac run uses `caffeinate -i` to prevent idle sleep while the tunnel process is running. On another operating system, invoke `cloudflared` directly. Use the generated HTTPS URL for `/`, `/studio` and same-origin API requests. No separate CORS origin or public development API port is required. Keep this process running alongside the production supervisor. Ending either process makes the public app unavailable.

Guest caches belong to the browser origin. Recreating the random tunnel hostname opens a different guest cache; account-owned trips remain in the server's persistent store and can be resumed after signing in at the new hostname. The public hostname is a connection route, not a storage or authentication backup.

## Persistent state and upgrades

`DETOUR_STATE_DIR` must be an absolute private directory outside `web/`, on storage retained across restarts. The native example uses the ignored `.detour-production/` directory. Its state directories are mode 0700; the generated signing key is mode 0600. Only one production supervisor may use a state directory at a time.

| Path or setting | Purpose |
| --- | --- |
| `app/` | Managed materialization of the sealed release at a stable project path |
| `graph/` (`JAC_DATA_PATH`) | Jac graph data path |
| `jac-cache/` (`JAC_CACHE_HOME`) | Jac runtime cache and embedded PostgreSQL storage |
| `planner/` (`PLANNER_DATA_DIR`) | Private SQLite jobs, attachments, source captures and weather cache |
| `jwt-secret` | Stable local signing key when `JAC_SERVE_AUTH_SECRET` is not supplied |

The supervisor verifies the bundle digest and materializes it at the same `state/app` path on upgrades. This stable path preserves Jac's embedded-database identity across artifact versions. Retain the state directory and signing key when replacing release code. An explicit `JAC_SERVE_AUTH_SECRET` must contain at least 32 characters and remain stable across restarts. An existing externally managed database can be supplied through `JAC_DB_URL`.

For a consistent backup, take a PostgreSQL logical backup using the configured database connection and retain the private planner files and signing key. Stop the worker while taking a matching queue/file snapshot. A filesystem copy of PostgreSQL storage is safe only after PostgreSQL has been cleanly stopped. `app/` is replaceable release code; it is not a substitute for the database, planner files or signing key.

Other supported overrides are `DETOUR_BUNDLE` (absolute `.jab` path), `JAC_BIN`, `WORKER_PYTHON` and `PLAYWRIGHT_BROWSERS_PATH`. Keep one host/replica per SQLite queue; separate local SQLite volumes do not form a distributed worker queue.

## Optional container package

`Dockerfile` packages the pinned compiler, Python worker, Chromium and PostgreSQL. `.dockerignore` excludes private configuration, local databases, runtime data and captures. The image runs as a non-root user and expects a persistent volume at `/data/detour`.

```sh
docker build -t detour .
docker run --rm --name detour -p 8080:8000   --mount type=volume,source=detour-state,target=/data/detour   --env-file /absolute/private/detour.env detour
```

The private environment file supplies `ANTHROPIC_API_KEY`; it is passed at runtime, not copied into the image. Container packaging is provided, but an actual Docker image build/run has not been verified in the current environment because no Docker engine is available. The selected native deployment and public HTTPS journey are verified as described above.

There is no root `render.yaml` to auto-provision a paid service. `render-paid.example.yaml` is an explicitly optional **paid** container/disk example, not the requested free deployment. `render-legacy.example.yaml` preserves the unsupported historical single-process blueprint. Neither example is an active free-hosting configuration.
