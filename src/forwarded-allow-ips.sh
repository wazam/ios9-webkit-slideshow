#!/bin/sh
# Trust X-Forwarded-For only from the addresses in FORWARDED_ALLOW_IPS, so the access log shows a proxied
# client's real IP and nobody else can fake theirs. Writes one set_real_ip_from line per address or CIDR
# range for /etc/nginx/conf.d/forwarded-allow-ips.conf to include; * trusts every address.
# 15-defaults.envsh sets the default before this runs.
# -f turns off globbing, so a * entry stays a literal instead of matching file names.
set -euf

conf=/tmp/forwarded-allow-ips.conf
value=$(printf '%s' "$FORWARDED_ALLOW_IPS" | tr -d ' ')
bad=

: > "$conf"
for entry in $(printf '%s' "$value" | tr ',' ' '); do
    case $entry in
        '*') printf 'set_real_ip_from 0.0.0.0/0;\nset_real_ip_from ::/0;\n' >> "$conf" ;;
        # IP addresses and CIDR ranges only: nginx would also take a host name and look it up
        *[!0-9A-Fa-f.:/]*) bad=1 ;;
        *) printf 'set_real_ip_from %s;\n' "$entry" >> "$conf" ;;
    esac
done

# nginx checks each address itself; report a bad one under the setting's name instead of nginx's
if [ -n "$bad" ] || [ ! -s "$conf" ] || ! error=$(nginx -t -q 2>&1); then
    echo "FORWARDED_ALLOW_IPS must be comma-separated IP addresses or CIDR ranges, or *, got '$FORWARDED_ALLOW_IPS'. ${error:-}" >&2
    exit 1
fi
