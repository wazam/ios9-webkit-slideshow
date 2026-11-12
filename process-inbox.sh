#!/bin/sh
# Watches pictures/_inbox/ for dropped photos, converts HEIC to JPEG, moves
# everything into the matching spot in pictures/ (mirroring inbox's own
# subfolder structure), and removes the original from inbox only after a
# verified successful write. Content is hashed against a small persistent
# manifest so the same photo dropped twice never ends up duplicated.
DIR=/usr/share/nginx/html/pictures
INBOX="$DIR/_inbox"
MANIFEST="$DIR/.inbox-manifest"

# Logs why the inbox is off and how to fix it. Silent when pictures/ sits on
# a read-only mount (a read-only photo library is a supported setup with no
# inbox), or doesn't exist (nothing mounted, so there are no photos either).
warn_not_writable() {
  [ -d "$DIR" ] || return
  # The options of the mount that holds pictures/: the longest mount point
  # that is pictures/ itself or one of its parent folders.
  if awk -v d="$DIR" '
    ($2 == d || $2 == "/" || index(d, $2 "/") == 1) && length($2) >= best { best = length($2); opts = $4 }
    END { exit opts !~ /^ro(,|$)/ }' /proc/mounts; then
    return
  fi

  if [ -w "$DIR" ]; then target="$INBOX"; name="pictures/_inbox/"; else target="$DIR"; name="pictures/"; fi
  owner=$(stat -c %u:%g "$target")
  me="$(id -u):$(id -g)"

  if [ "${owner%%:*}" = "$(id -u)" ]; then
    echo "process-inbox: $name is owned by $me but isn't writable (mode $(stat -c %a "$target")), so the inbox is off. To turn it on: chmod -R u+w ./pictures" >&2
  elif [ "${owner%%:*}" = 0 ]; then
    echo "process-inbox: $name is owned by root and the container runs as $me, so the inbox is off. To turn it on, give the folder to the container's user: sudo chown -R $me ./pictures" >&2
  else
    echo "process-inbox: $name is owned by $owner and the container runs as $me, so the inbox is off. To turn it on, give the folder to the container's user (sudo chown -R $me ./pictures), or set user: \"$owner\" in compose.yaml" >&2
  fi
}

# Warns only on the first run ("startup"), so a wrong owner is logged once per
# container start instead of every scan. Fixing the owner while the container
# runs turns the inbox on at the next scan.
process_inbox() {
  if ! mkdir -p "$INBOX" 2>/dev/null || [ ! -w "$DIR" ] || [ ! -w "$INBOX" ]; then
    [ "$1" = startup ] && warn_not_writable
    return
  fi

  find "$INBOX" -type f 2>/dev/null | while IFS= read -r f; do
    rel=${f#"$INBOX"/}

    case "$rel" in
      *.[hH][eE][iI][cC]) destrel="${rel%.*}.jpg"; needs_convert=1 ;;
      *.[jJ][pP][gG]|*.[jJ][pP][eE][gG]|*.[pP][nN][gG]|*.[gG][iI][fF]) destrel="$rel"; needs_convert=0 ;;
      *) continue ;;
    esac

    hash=$(sha256sum "$f" | cut -d' ' -f1)

    if [ -f "$MANIFEST" ] && grep -q "^$hash	" "$MANIFEST"; then
      rm -f "$f"
      continue
    fi

    dest="$DIR/$destrel"
    mkdir -p "$(dirname "$dest")"

    if [ -e "$dest" ]; then
      existing_hash=$(sha256sum "$dest" | cut -d' ' -f1)
      if [ "$existing_hash" = "$hash" ]; then
        # Identical content already sitting at this exact destination path,
        # even though it never came through the inbox (so the manifest never
        # recorded it). Treat it as the duplicate it is instead of renaming,
        # and backfill the manifest so future lookups benefit too.
        if [ ! -f "$MANIFEST" ] || ! grep -q "^$hash	" "$MANIFEST"; then
          printf '%s\t%s\n' "$hash" "$destrel" >> "$MANIFEST"
        fi
        rm -f "$f"
        continue
      fi

      base=${destrel%.*}
      ext=${destrel##*.}
      n=1
      while [ -e "$DIR/${base} ($n).$ext" ]; do
        n=$((n + 1))
      done
      destrel="${base} ($n).$ext"
      dest="$DIR/$destrel"
    fi

    tmp="$(dirname "$dest")/.inbox-tmp-$$.${destrel##*.}"

    if [ "$needs_convert" = "1" ]; then
      if ! heif-convert "$f" "$tmp" >/dev/null 2>&1; then
        echo "process-inbox: failed to convert $rel" >&2
        rm -f "$tmp"
        continue
      fi
    else
      cp "$f" "$tmp"
    fi

    if [ ! -s "$tmp" ]; then
      echo "process-inbox: empty output for $rel" >&2
      rm -f "$tmp"
      continue
    fi

    mv "$tmp" "$dest"
    printf '%s\t%s\n' "$hash" "$destrel" >> "$MANIFEST"
    rm -f "$f"
  done
}

process_inbox startup
( while true; do sleep "${INBOX_SCAN_SECONDS:-30}"; process_inbox; done ) &
