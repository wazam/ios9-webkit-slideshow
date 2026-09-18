FROM nginxinc/nginx-unprivileged:alpine

ARG GIT_COMMIT
ARG BUILD_DATE
ARG IMAGE_VERSION

LABEL org.opencontainers.image.title="iOS 9 WebKit Slideshow" \
    org.opencontainers.image.description="Minimal, dependency-free photo slideshow built to run on genuinely old hardware, like an iPad 3 stuck on iOS 9.3.5 Safari" \
    org.opencontainers.image.version="${IMAGE_VERSION:-unknown}" \
    org.opencontainers.image.source="https://github.com/wazam/ios9-webkit-slideshow" \
    org.opencontainers.image.documentation="https://github.com/wazam/ios9-webkit-slideshow#readme" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.authors="James Wazam" \
    org.opencontainers.image.vendor="wazam" \
    org.opencontainers.image.revision="${GIT_COMMIT:-unknown}" \
    org.opencontainers.image.created="${BUILD_DATE:-unknown}"

ENV NGINX_ENVSUBST_OUTPUT_DIR=/usr/share/nginx/html
ENV SLIDESHOW_DELAY_SECONDS=10
ENV BROWSER_REFRESH_MINUTES=15
ENV SLIDESHOW_SHUFFLE=true

USER root

RUN apk add --no-cache libheif-tools shadow su-exec

COPY index.html.template /etc/nginx/templates/index.html.template
COPY apple-touch-icon.png /usr/share/nginx/html/apple-touch-icon.png
COPY process-inbox.sh /docker-entrypoint.d/35-process-inbox.sh
COPY generate-photos.sh /docker-entrypoint.d/40-generate-photos.sh
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /docker-entrypoint.d/35-process-inbox.sh /docker-entrypoint.d/40-generate-photos.sh /entrypoint.sh && \
    chown -R nginx:nginx /usr/share/nginx/html

# Stays root: entrypoint.sh needs it to adjust the nginx user's UID/GID to
# match PUID/PGID before dropping privileges itself via su-exec.

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q --spider http://127.0.0.1:8080/ || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]