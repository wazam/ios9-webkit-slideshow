#!/bin/sh
generate() {
  DIR=/usr/share/nginx/html/pictures
  OUT=/usr/share/nginx/html/photos.js
  echo "var photos = [" > "$OUT"
  first=1
  find "$DIR" -type d \( -name ignore -o -name _inbox \) -prune -o -type f -print 2>/dev/null | sort | while IFS= read -r f; do
    case "$f" in
      *.[jJ][pP][gG]|*.[jJ][pP][eE][gG]|*.[pP][nN][gG]|*.[gG][iI][fF]) ;;
      *) continue ;;
    esac
    rel=${f#"$DIR"/}
    if [ "$first" = "1" ]; then
      echo "  \"pictures/$rel\"" >> "$OUT"
      first=0
    else
      echo "  ,\"pictures/$rel\"" >> "$OUT"
    fi
  done
  echo "];" >> "$OUT"
}

generate
( while true; do sleep "${SERVER_SCAN_SECONDS:-60}"; generate; done ) &