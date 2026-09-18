#!/bin/sh
# Watches pictures/_inbox/ for dropped photos, converts HEIC to JPEG, moves
# everything into the matching spot in pictures/ (mirroring inbox's own
# subfolder structure), and removes the original from inbox only after a
# verified successful write. Content is hashed against a small persistent
# manifest so the same photo dropped twice never ends up duplicated.
process_inbox() {
  umask 000
  DIR=/usr/share/nginx/html/pictures
  INBOX="$DIR/_inbox"
  MANIFEST="$DIR/.inbox-manifest"

  mkdir -p "$INBOX" 2>/dev/null || return

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

process_inbox
( while true; do sleep "${INBOX_SCAN_SECONDS:-30}"; process_inbox; done ) &
