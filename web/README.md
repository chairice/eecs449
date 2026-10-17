# Detour web application

The current application has a Detour landing page and directly reachable
planning, results, trips, trip-detail, settings, and not-found routes. The
composer and preferences are disabled previews; there is no route search or
trip persistence yet. Results recover from a missing draft, trips show an
empty state, and unavailable trip IDs show a not-found state.

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

## Baseline validation

From the repository root:

```bash
bash scripts/validate.sh
```

The script rejects a different Jac version, checks all source files with
`jac check .`, runs `jac test tests/domain_tests.jac -v`, then builds with
`jac build --as client`. It exits on any failure. If Jac is not on PATH, use
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
| `server/models.jac` | Canonical domain objects, validation, and fixture JSON codecs. |
| `tests/domain_tests.jac` | Domain boundary and serialization regression tests. |
| `components/` | Shared `Brand`, `PublicHeader`, and `AppShell`, plus landing sections. |

`AppShell` receives `dark`, `publicPage`, `minimalHeader`, `activePath`, and
`navigationEnabled` from its caller and accepts page content through
`children`, plus an optional `footer` rendered outside the main landmark.
The landing uses its public variant, application routes share primary
navigation, and unknown public URLs use the minimal brand-only header. The guest profile is
display-only until authentication exists. Mobile navigation stays visible,
and controls use at least 44px targets. Shell theme colors are centralized
in `styles.css`; the legacy `Theme` helpers reference those same variables.

| Route | Current behavior |
|---|---|
| `/` | Detour overview, illustrative request, and working planning link. |
| `/plan` | Disabled composer preview. |
| `/plan/results` | Missing-request recovery; no invented search results. |
| `/trips` | Empty saved-trips state. |
| `/trips/:id` | Unavailable-trip state until persistence is connected. |
| `/settings` | Disabled preference preview and disconnected provider statuses. |
| Any other path | 404 and link back to planning; no app navigation. |

Use `Link` from `@jac/runtime` for internal navigation. Keep route components
in `pages/`; do not add a second manual router. Loading and provider-error
states will be wired to real planning state in their dedicated feature.
