# Detour web application

The app has a landing page, Atlas, planning/results, browser-local saved trips,
trip detail, and a not-found route. The commuter planner ranks synthetic
routes from Ann Arbor to Chicago, Detroit, Grand Rapids, Lansing, Toledo and
Cleveland. Atlas is a separate travel journal and future-intent
canvas with local place lookup, optional LLM proposals, and optional OSRM road
geometry. Neither flow purchases travel. See [planning preview](../docs/planning-preview.md)
and [Atlas design](../docs/atlas-design.md) for their separate boundaries.

## Toolchain and first setup

The supported compiler is **Jac 0.37.14**, pinned in `jac.toml`. Jac syntax is
version-sensitive: this release infers client placement from JSX and imports,
uses ordinary `.jac` filenames, and no longer accepts `cl { ... }` wrappers.
Its standalone binary includes Python, Bun, and the client compiler; do not
install the former `jaclang`/`jac-client` pip plugins into a separate virtualenv.
The repository also pins **Node 22.11.0** in `.nvmrc` for JavaScript tooling and
CI; Jac's own dependency installation and bundling use its bundled Bun runtime.

Install the pinned compiler with the official installer:

```bash
curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh | bash -s -- --version 0.37.14
export PATH="$HOME/.local/bin:$PATH"
jac --version
```

From the repository root:

```bash
nvm install                 # optional when using nvm for Node tooling
nvm use
cd web
jac install
```

Initial installation/build needs network access for dependencies. Jac stores
generated packages, bundles, and local runtime data under ignored `web/.jac/`.
`jac.toml` is the dependency source of truth; the generated client package
manifest and Bun lockfile live under `.jac/client/`. Dependency ranges are
resolved on a fresh install, so the compiler is pinned but transitive npm
dependencies are not yet frozen in the repository.

## Development server

From `web/`:

```bash
jac run --dev main.jac
```

Open http://localhost:8000. Client edits hot-reload; restart for server changes.
The development API uses port 8001. Stop with Ctrl+C. `jac run --show` prints
the resolved entry point and serving mode. Run Jac commands from `web/` so
they use this project's configuration.

## Atlas configuration

No key is needed for local place lookup, manual editing, illustrative flights,
browser storage, or the limited explicit-route parser. Open `/atlas` after
starting the app. A sample rules request is `DTW -> JFK -> BOS`; confirm modes
and resolve all remaining details before saving.

- `ANTHROPIC_API_KEY`: optional server-only credential for natural-language
  creation/refinement. Never put it in client code or Git. Atlas sends only the
  submitted sentence and selected itinerary fields, not other journeys or notes.
- `ATLAS_MODEL`: optional model override; defaults to `DETOUR_MODEL` or
  `claude-haiku-5-5`, matching the existing interpreter. Model access depends on
  your provider account; failures visibly fall back to rules/manual editing.
- `ATLAS_OSRM_BASE`: optional operator-controlled route endpoint. Default:
  `https://routing.openstreetmap.de/routed-car/route/v1/driving/`.
  The public service receives/logs the selected endpoints. No paid fallback.

Road calls are gated at one/second per process, with a 64-entry one-hour cache
(errors 15 seconds), 10-second timeout, and response/geometry bounds. AI calls
have a 12-second timeout and a 30/hour per-process ceiling, at least two seconds
apart. These are demo safeguards, not distributed production quotas. Proposals
support up to 24 stops; all output needs review. Simplified US boundaries can
reject valid coastal roads. Use a suitable self-hosted route backend before
scaling. See [data documentation](../docs/atlas-data.md) for attribution and
coverage. Atlas does not invoke the commuter planner or book anything.

## Baseline validation

From the repository root:

```bash
bash scripts/validate.sh
```

The script rejects a different Jac version, checks all source files with
`jac check .`, runs every suite with `jac test -d tests/ -v`, builds with
`jac build main.jac`, then tests the emitted client helpers with Node. It exits
on any failure. If Jac is not on PATH, use
`JAC_BIN=/absolute/path/to/jac bash scripts/validate.sh`. The same script runs
for pull requests and pushes to `main` in `.github/workflows/validate.yml`.
The production client is emitted into `web/.jac/client/dist/`; it is not a
deployed app or a bundled server. Browser smoke check: open every route below
directly, follow internal links, use browser back/forward, and resize to mobile.
Jac serves extensionless paths through its SPA fallback. Another production
host must serve the app HTML for those same paths.

Jac 0.37.14 currently reports these nonfatal diagnostics on this client.
They remain visible; no diagnostic classes are globally suppressed:

- `W1037`: deliberate `any` values at browser and JSX children boundaries.
- `W2001`: intrinsic HTML closing tags are reported as possibly undefined.
- `W2003`: compiler-generated React state setters are reported as unused.
- `W1051`: some built-in `@jac/runtime` routing exports lack resolved checker types.

Missing-import warnings (`W1100`) before dependency installation should
disappear after `jac install`; investigate new warnings rather than treating
them as part of this baseline. A successful check/build does not replace
interaction testing as new functionality is added.

## Source map

| File | Responsibility |
|---|---|
| `main.jac` | Renders the generated file-based router's children. |
| `pages/layout.jac` | Persistent shell, active navigation, and color-scheme subscription. |
| `pages/` | Public `JsxPage` exports declare routes; `JsxLayout` declares the shared layout. |
| `theme.jac` | Light/dark themes, fonts, and shared style helpers. |
| `styles.css` | Shared semantic color, spacing, typography, radius, elevation, focus, and responsive tokens. |
| `browser.jac` | Typed wrappers around media queries and DOM styling. |
| `client/composer_model.jac` | Raw form input, exact local validation, and the typed client draft. |
| `components/TripComposer.jac` | Accessible input form and honest validated-request summary. |
| `tests/composer_tests.jac` | Calendar, time, currency, required-field, mode, and input-preservation tests. |
| `server/models.jac` | Canonical domain objects, validation, and fixture JSON codecs. |
| `tests/domain_tests.jac` | Domain boundary and serialization regression tests. |
| `components/` | Shared `Brand`, `PublicHeader`, and `AppShell`, plus landing sections. |
| `tailwind.css` | Tailwind v4 theme and utilities, layered above the hand-written styles. |
| `client/account.jac` | Email/password sign-up, login, and logout over Jac's built-in user store. |
| `components/AuthPanels.jac` | Home-page log-in and create-account panels. |
| `components/AccountMenu.jac` | Header account control: Log in, or the signed-in email and Log out. The Trips tab shows the saved-trip count. |
| `components/FloatingField.jac` | Input frame with a floating label, used by the account forms. |
| `server/providers/weather.jac` | National Weather Service forecasts and alerts at hourly points along each route. |
| `server/weather_rules.jac` | Pure rules turning weather evidence into Low, Moderate, High or Unknown. |
| `fixtures/weather/` | Recorded NWS responses for `tests/weather_tests.jac`; tests never call the live API. |

## Styling and accounts

Tailwind v4 is layered on top of the original CSS rather than replacing it.
`tailwind.css` loads Tailwind's theme and utilities without its Preflight reset,
and every hand-written stylesheet is wrapped in `@layer legacy`, declared below
`utilities`, so a utility class always wins over a hand-written rule on the same
element. Rules that override Leaflet's own (unlayered) stylesheet sit outside
the layer at the end of `styles.css` and `atlas.css`; keep new Leaflet
overrides there. Without Preflight, buttons and lists keep browser defaults, so
add `border-0` or `list-none p-0` where a component needs them.

Accounts use `jacSignup`/`jacLogin` from `@jac/runtime`: the server stores
hashed passwords and issues the session token; no email is sent. The browser
remembers the signed-in email so the header can show it, and saved trips are
stored under `detour.savedTrips.v1:<email>` while signed in (the shared
`detour.savedTrips.v1` list otherwise). Planning and Atlas never require an
account. Locally the dev server creates its own JWT secret; deployments set
`JAC_SERVE_AUTH_SECRET` (already in `render.yaml`).

## Weather

`plan_trip` asks `api.weather.gov` (free, no key) for the hourly forecast and
active alerts at each vehicle's start and end and at a point on its path for
every further hour aboard, at the time the traveler is there. Responses are
cached (grid lookups a day, forecasts 15 minutes, alerts 5 minutes) and fetched
in parallel within an 8-second budget. `server/weather_rules.jac` then sets
each route's level:

- **High**: a warning, or a severe or extreme alert, in force at any point.
- **Moderate**: a watch, advisory or moderate alert; an hour at least 50% likely
  to bring snow, sleet, freezing rain, ice or thunderstorms; or wind of 35 mph
  or more.
- **Low**: every point's forecast and alerts were read and none of the above.
- **Unknown**: any point couldn't be read. Unknown is never treated as safe.
- **Not yet forecast**: the trip ends past the ~6-day forecast. The route
  carries `weather_from` (when forecasts will cover it), its weather stays
  unknown without counting as missing data, and the risk badge is set by delay
  and connection risk; the card says "Forecast from Sat, Nov 14". A Moderate
  or High reading on the part already forecast still counts.

Saved trips keep each leg's route, its delay and connection levels, and its
risk as of saving. Opening a trip asks `trip_weather` for that route's weather
now, using the same rules as search, and shows "Risks now"; trips saved before
routes were kept, or a failed check, fall back to "Risks when saved".
`trip_weather` takes at most six legs, each under a day long, and stores nothing.

Results cards show the forecast's words under the risk badge, and the booking
card says what set the level. The ranker stays pure; the API passes it the
evidence. Set `DETOUR_WEATHER=off` to skip live lookups, and
`DETOUR_NWS_CONTACT` to a contact address on deployed servers (NWS asks
callers to identify themselves). The thresholds are the place to apply a
fitted delay model later.

`AppShell` receives `dark`, `publicPage`, `minimalHeader`, `activePath`, and
`navigationEnabled` from its caller and accepts page content through
`children`, plus an optional `footer` rendered outside the main landmark.
The landing uses its public variant, application routes share primary
navigation, and unknown public URLs use the minimal brand-only header. The guest profile is now
replaced by the account control (Log in, or the signed-in email and Log out). Mobile navigation stays visible,
and controls use at least 44px targets. Shell theme colors are centralized
in `styles.css`; the legacy `Theme` helpers reference those same variables.

| Route | Current behavior |
|---|---|
| `/` | Detour overview, destination carousel, and log-in / create-account panels. |
| `/plan` | Local validation, pending/retry states, and read-only synthetic fixture search; no LLM calls. |
| `/plan/results` | Ranked fixture routes, each dated, or explicit errors; arrive-by searches cover every day from now to the deadline. Travelers can sort by Recommended, price, or soonest/latest departure (departure sorts group by day; the top choice stays marked Recommended); risk isn't a sort while it is only a level. Round trips are two numbered steps (a return may be the same day, for day trips), and returns are limited to those leaving after the chosen outbound arrives; the default outbound is the best one some return can follow; missing-request recovery on direct links. |
| `/trips` | Saved-trip cards (this browser, per account when signed in) with remove, or an empty state. |
| `/trips/:id` | One saved trip with its route, map, and Remove trip; unavailable state for unknown ids. |
| Any other path | 404 and link back to planning; no app navigation. |

Use `Link` from `@jac/runtime` for internal navigation. Keep route components
in `pages/`; do not add a second manual router. Loading and provider-error
states reflect the actual fixture planning request; no fixed loading timer is used.

## Composer contract

`TripComposer` accepts an optional initial `ComposerInput`, an optional
`earliestDate`, `busy`, `submitLabel`, and an async
`onValidDraft: Callable[[ComposerDraft], None]` (awaited by the form; Jac types
async functions by their resolved return value). Input is
copied on changes and is never cleared after a failed submission. The callback
fires only for a complete, locally valid structured request. Natural-language
text is optional while using the structured fallback and cannot overwrite
explicit fields. It is retained in `request_text` for a future parser.

The draft uses the server contract's field names and string enum values;
currency is exact integer USD cents, an absent budget is `None`, and zero is
a valid budget. Validation rejects impossible Gregorian dates, malformed
24-hour times, identical locations, invalid decimal budgets, fractional or
negative transfer buffers, and an empty mode selection. Date/time remain local
intent. The caller can inject an earliest date resolved in the departure or
arrival location's time zone; the current page does not guess that boundary
from the device's time zone. No current-date restriction is applied yet.

Without a callback, the built-in summary demonstrates the payload without
claiming that a search ran or a plan was saved. The planning page instead calls
`server.api.plan_trip` with the nine explicit canonical fields; optional prose
is never sent to this endpoint. Controls are disabled during the request, a
synchronous guard rejects duplicates, and responses after unmount are ignored.
Transport failures retain the form and allow another submission. Browser Back
and Edit restore the submitted request and description through history state;
this is not durable storage. The mapper rejects malformed history state.

Run pure validation with `jac test tests/composer_tests.jac -v` from `web/`.
After a full `jac build main.jac`, run
`node --test ../scripts/test-client-composer.mjs` for the emitted browser
payload/restoration boundary. It deliberately checks plain JavaScript records:
Jac 0.37.14's `isinstance(value, dict)` does not recognize history-state objects.
Browser checks should cover
blank submission, summary focus, field error links, successful validation,
retained structured fields after editing the description, and mobile layout.
