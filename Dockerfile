FROM nginxinc/nginx-unprivileged:1.31-alpine

# The base image sets its own labels. maintainer replaces its NGINX Docker
# Maintainers, and version, revision and created are emptied so local builds
# don't show nginx's values; Docker Publish sets the real ones.
LABEL org.opencontainers.image.title="iOS 9 WebKit Slideshow" \
    org.opencontainers.image.description="Minimal, dependency-free photo slideshow for old hardware, built for an iPad 3 on iOS 9.3.6 Safari" \
    org.opencontainers.image.url="https://github.com/wazam/ios9-webkit-slideshow" \
    org.opencontainers.image.source="https://github.com/wazam/ios9-webkit-slideshow" \
    org.opencontainers.image.documentation="https://github.com/wazam/ios9-webkit-slideshow#readme" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.authors="James Wazam" \
    org.opencontainers.image.vendor="wazam" \
    org.opencontainers.image.base.name="docker.io/nginxinc/nginx-unprivileged:1.31-alpine" \
    org.opencontainers.image.version="" \
    org.opencontainers.image.revision="" \
    org.opencontainers.image.created="" \
    maintainer="James Wazam"

ENV NGINX_ENVSUBST_OUTPUT_DIR=/tmp

USER root

# apk upgrade takes Alpine's security updates that the base image doesn't have
# yet; curl ships with the base image but nothing here uses it.
RUN apk upgrade --no-cache && \
    apk add --no-cache libheif-tools && \
    apk del --no-cache curl

COPY src/index.html.template /etc/nginx/templates/index.html.template
COPY src/apple-touch-icon.png /usr/share/nginx/html/apple-touch-icon.png
COPY --chmod=755 src/process-inbox.sh /docker-entrypoint.d/35-process-inbox.sh
COPY --chmod=755 src/generate-photos.sh /docker-entrypoint.d/40-generate-photos.sh

# Defaults for settings the startup scripts read. compose.yaml sends its own
# copy of each, so these cover docker run without compose and empty values.
# They're set at startup rather than with ENV, which a bare "- VAR" entry would
# remove. The entrypoint sources .envsh files, so these exports reach the
# scripts after it: 16-forwarded-allow-ips.sh, and 20-envsubst-on-templates.sh,
# which fills in index.html. ":-" also covers a variable set to an empty value.
COPY --chmod=755 <<'EOF' /docker-entrypoint.d/15-defaults.envsh
export SLIDESHOW_INTERVAL_SECONDS="${SLIDESHOW_INTERVAL_SECONDS:-10}"
export BROWSER_REFRESH_MINUTES="${BROWSER_REFRESH_MINUTES:-15}"
export SLIDESHOW_SHUFFLE="${SLIDESHOW_SHUFFLE:-true}"
FORWARDED_ALLOW_IPS=$(printf '%s' "${FORWARDED_ALLOW_IPS:-}" | tr -d ' ')
export FORWARDED_ALLOW_IPS="${FORWARDED_ALLOW_IPS:-127.0.0.1,::1}"
EOF

# Behind a reverse proxy, log the client's IP from X-Forwarded-For, trusted
# only from the addresses 16-forwarded-allow-ips.sh writes at startup. Redirects
# nginx makes itself use a relative Location, so they keep the browser's scheme.
COPY --chmod=755 src/forwarded-allow-ips.sh /docker-entrypoint.d/16-forwarded-allow-ips.sh
COPY <<'EOF' /etc/nginx/conf.d/forwarded-allow-ips.conf
real_ip_header X-Forwarded-For;
include /tmp/forwarded-allow-ips.conf;
absolute_redirect off;
EOF

# index.html (written by envsubst at startup) and photos.js (rewritten by
# generate-photos.sh) are links into /tmp, so /usr/share/nginx/html stays
# owned by root and the container can run with a read-only filesystem.
RUN ln -sf /tmp/index.html /usr/share/nginx/html/index.html && \
    ln -sf /tmp/photos.js /usr/share/nginx/html/photos.js

USER 1000:1000

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --start-interval=5s --retries=3 \
    CMD wget -q --spider http://127.0.0.1:8080/ || exit 1
