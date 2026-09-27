# Everyday Agent landing page

The project's landing page, written entirely in [Jac](https://www.jaseci.org/), styles included, using the `jac-client` plugin (Jac compiles `.cl.jac` files to a React app).

## Run it locally

Requirements: Python 3.12+ and Node.js 18+ (Vite, used under the hood, does not run on Node 16).

```bash
# from the repo root
python3 -m venv .venv
.venv/bin/pip install jaclang jac-client

cd web
../.venv/bin/jac install
../.venv/bin/jac start main.jac      # add --dev for hot reload
```

Then open http://localhost:8000.

If `jac` fails to download Bun with `CERTIFICATE_VERIFY_FAILED` (common with the python.org installer on macOS), run the "Install Certificates.command" script in your Python folder, or run `export SSL_CERT_FILE=$(../.venv/bin/python -m certifi)` before the commands above.

## Where things are

| File | What it holds |
|---|---|
| `main.jac` | Entry point; mounts the page at `/`. |
| `content.cl.jac` | All the page copy: goals, use cases, and "how it works" steps. Edit text here. |
| `frontend.cl.jac` | Page layout and page-wide state (dark mode, screen size). |
| `theme.cl.jac` | Light and dark color themes, fonts, and shared style helpers. |
| `browser.cl.jac` | Small typed wrappers for the browser APIs the page uses (media queries, fonts, page background). |
| `components/` | `SiteHeader`, `Hero`, `CardSection` (reused for each card grid), `SiteFooter`. Each styles itself with inline style dicts built from the theme. |

Check your changes with `../.venv/bin/jac check main.jac *.cl.jac components/*.cl.jac`. Warnings about `any` types in `browser.cl.jac` and the `react` import are expected.
