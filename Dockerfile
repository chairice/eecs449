# Both processes share one host and one mounted state directory. Run one replica.
FROM node:22.11.0-bookworm-slim AS node
FROM python:3.13-slim-bookworm

ARG JAC_VERSION=0.37.14
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    JAC_BIN=/opt/jac/bin/jac \
    WORKER_PYTHON=/opt/worker/bin/python \
    PLAYWRIGHT_BROWSERS_PATH=/opt/browsers \
    DETOUR_STATE_DIR=/data/detour \
    JAC_PG_VERSION=15 \
    PORT=8000 \
    PATH=/opt/jac/bin:/opt/worker/bin:/usr/local/bin:/usr/bin:/bin

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl postgresql-15 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 app \
    && mkdir -p /opt/jac/bin /app /data/detour \
    && curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh -o /tmp/install-jac.sh \
    && bash /tmp/install-jac.sh --version "$JAC_VERSION" \
    && mv /root/.local/bin/jac /opt/jac/bin/jac \
    && rm /tmp/install-jac.sh \
    && python -m venv /opt/worker

WORKDIR /app
COPY workers/requirements.lock workers/requirements.lock
RUN /opt/worker/bin/python -m pip install -r workers/requirements.lock \
    && /opt/worker/bin/python -m playwright install --with-deps chromium

# .dockerignore excludes local databases, credentials, browser captures and caches.
COPY web web
COPY workers workers
COPY scripts scripts
RUN chown -R app:app /app /opt/jac /opt/worker /opt/browsers /data/detour
USER app
RUN bash scripts/build-studio.sh

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=12s --start-period=180s --retries=3 \
    CMD ["/opt/worker/bin/python", "/app/scripts/studio-health.py"]
CMD ["/opt/worker/bin/python", "/app/scripts/serve-studio.py"]
