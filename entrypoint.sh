#!/bin/sh
# Runs as root before anything else. Adjusts the baked-in "nginx" user to
# match PUID/PGID (so it can be made to line up with whichever host user
# owns the pictures/ bind mount), re-chowns everything that user needs to
# write to, then drops privileges and hands off to the base image's own
# entrypoint chain (envsubst templating, generate-photos.sh,
# process-inbox.sh, then nginx itself) exactly as it would run unmodified.
set -e

PUID=${PUID:-1000}
PGID=${PGID:-1000}

groupmod -o -g "$PGID" nginx
usermod -o -u "$PUID" nginx

# The stock access.log/error.log are symlinks to /dev/stdout/stderr, a trick
# that only works for the process that originally owned those descriptors.
# Once su-exec below changes this process's UID, the kernel marks it
# non-dumpable (a standard uid-change security measure), which blocks even
# its own fresh open() of /proc/self/fd/* — so nginx fails to start with
# "Permission denied" opening its log files. Real files sidestep this
# entirely (plain filesystem permissions, no /proc/self involved), bridged
# to actual container output by a tail process that stays root, since root
# never goes through a uid transition and is unaffected.
rm -f /var/log/nginx/access.log /var/log/nginx/error.log
chown nginx:nginx /var/log/nginx
tail -F -q /var/log/nginx/access.log /var/log/nginx/error.log 2>/dev/null &

# Best-effort: pictures/ may be (partially) read-only by design (see the
# read-only deployment mode in the README), in which case chown legitimately
# can't touch some paths under it. That's expected, not fatal, so don't let
# set -e kill startup over it.
chown -R nginx:nginx /usr/share/nginx/html /var/cache/nginx || true

exec su-exec nginx /docker-entrypoint.sh "$@"
