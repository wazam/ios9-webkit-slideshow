FROM nginxinc/nginx-unprivileged:1.31-alpine

# The base image sets its own labels. maintainer replaces its NGINX Docker
# Maintainers, and version, revision and created are emptied so local builds
# don't show nginx's values; Docker Publish sets the real ones.
LABEL org.opencontainers.image.title="iOS 9 WebKit Slideshow" \
    org.opencontainers.image.description="Minimal, dependency-free photo slideshow for old hardware, built for an iPad 3 on iOS 9.3.6 Safari." \
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
ENV SLIDESHOW_INTERVAL_SECONDS=10
ENV BROWSER_REFRESH_MINUTES=15
ENV SLIDESHOW_SHUFFLE=true

USER root

# apk upgrade takes Alpine's security updates that the base image doesn't have
# yet; curl ships with the base image but nothing here uses it.
RUN apk upgrade --no-cache && \
    apk add --no-cache libheif-tools && \
    apk del --no-cache curl

COPY index.html.template /etc/nginx/templates/index.html.template
COPY apple-touch-icon.png /usr/share/nginx/html/apple-touch-icon.png
COPY process-inbox.sh /docker-entrypoint.d/35-process-inbox.sh
COPY generate-photos.sh /docker-entrypoint.d/40-generate-photos.sh

# index.html (written by envsubst at startup) and photos.js (rewritten by
# generate-photos.sh) are links into /tmp, so /usr/share/nginx/html stays
# owned by root and the container can run with a read-only filesystem.
RUN chmod +x /docker-entrypoint.d/35-process-inbox.sh /docker-entrypoint.d/40-generate-photos.sh && \
    ln -sf /tmp/index.html /usr/share/nginx/html/index.html && \
    ln -sf /tmp/photos.js /usr/share/nginx/html/photos.js

USER 1000:1000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q --spider http://127.0.0.1:8080/ || exit 1
