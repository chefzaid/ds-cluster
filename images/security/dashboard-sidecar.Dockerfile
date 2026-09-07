FROM ghcr.io/kiwigrid/k8s-sidecar:2.11.2@sha256:2912be006f62f9ea080194cf6d3afcd90daead8d101d0ba686a137a849f6a4f6
USER root
RUN apk upgrade --no-cache \
    && /app/.venv/bin/python -m pip install --no-cache-dir --upgrade pip==26.2.1 \
    && /usr/local/bin/python -m pip install --no-cache-dir --upgrade pip==26.2.1
USER 10001:10001
