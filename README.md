# iOS 9 WebKit Slideshow

<img src="apple-touch-icon.png" alt="Slideshow" width="96"> A minimal, dependency-free photo slideshow built to run on genuinely old hardware: originally an iPad 3 (iOS 9.3.5, stuck on ancient Safari/WebKit) repurposed as a wall-mounted photo display.

Just plain HTML/CSS/JS (ES5) served by nginx: no frameworks, no `fetch()`, no ES6+ syntax. Modern JS tooling simply won't run on browsers this old: [ImmichFrame](https://github.com/immichFrame/immichFrame)'s Svelte/TypeScript frontend was ruled out without testing, and [PhotoShow](https://github.com/thibaud-rohmer/PhotoShow)'s gallery grid loaded fine but its slideshow button silently did nothing on iOS 9 Safari.

## Demo

![The iPad 3 on its desk stand, crossfading between photos](slideshow-demo.gif)

The physical setup, crossfading between two photos on the iPad 3.

## Usage

The image is published to GitHub Container Registry (`ghcr.io/wazam/ios9-webkit-slideshow`) and Docker Hub (`wazam123/ios9-webkit-slideshow`).

**Required setup:** the container writes into `pictures/` (to process `_inbox/` drops), so set `PUID`/`PGID` in `compose.yaml` to match whoever owns your `pictures/` folder on the host (find yours with `id -u` and `id -g`; the default `1000` already matches the first user account on most single-user Linux/WSL setups). Once they match, the container and your own account always have full access to anything either side creates, no `chmod` ever needed, even for brand-new folders created later by a file manager or a family member organizing `_inbox/` drops into subfolders.

Running the published image (pulls `ghcr.io/wazam/ios9-webkit-slideshow`, as set in `compose.yaml`):

```bash
docker compose up -d
```

Building from source instead: `compose.override.yaml` swaps in a local `ios9-webkit-slideshow:local` tag and adds the `build: .` step, so a local build never overwrites the published GHCR image. This file auto-merges with `compose.yaml` on any plain `docker compose` command, no extra flags needed:

```bash
docker compose up -d --build
```

For faster iteration while actively developing, layer on `compose.dev.yaml` too, which shortens the slideshow/scan/refresh timings so changes show up in seconds instead of minutes (specifying any `-f` flags disables the automatic `compose.override.yaml` merge, so it has to be listed explicitly alongside the others):

```bash
docker compose -f compose.yaml -f compose.override.yaml -f compose.dev.yaml up -d --build
```

Then visit `http://<host>:8080`.

Add or remove photos by dropping files into the `pictures/` folder (bind-mounted from the host). No restart is required: the server rescans within `SERVER_SCAN_SECONDS`, then the browser picks up the updated list on its next reload, within `BROWSER_REFRESH_MINUTES`.

To add photos straight from an iPhone (or any format) without any conversion step, drop them into `pictures/_inbox/` (organize into subfolders there if you want; they land in the matching subfolder under `pictures/`, e.g. `pictures/_inbox/vacation2026/photo.heic` becomes `pictures/vacation2026/photo.jpg`). This is also why a GUI file manager like FileBrowser is optional rather than required: plain filesystem/network access to `pictures/_inbox/` is enough. The leading underscore is deliberate, it sorts the folder to the top of most file managers (FileBrowser, Windows Explorer, `ls`, etc.), ahead of `ignore/` and any of your own photo folders, so it's easy to find at a glance.

### Pointing at an existing photo folder instead (read-only)

If you already have a photo library elsewhere and don't want or need the inbox/HEIC-conversion feature, mount it read-only instead by adding `:ro` to the volume line in `compose.yaml`:

```yaml
volumes:
  - /path/to/your/existing/photos:/usr/share/nginx/html/pictures:ro
```

This works with any host path, not just `pictures/` in this repo. `PUID`/`PGID` don't need to match anything in this mode either, since the container never writes to a read-only mount. There's nothing else to set up: the inbox feature simply does nothing, since it only acts if a `pictures/_inbox/` folder exists, so a plain read-only library with no such folder is left untouched (no errors, no write attempts). `ignore/` folders still work identically either way. The trade-off: a `.heic` file dropped straight into a read-only-mounted folder is simply never picked up, since there's no inbox to convert it and the scanner only recognizes already-supported image formats.

You don't have to choose one or the other: an existing library can also be mounted read-only *alongside* the managed `pictures/` tree, nested at a subpath instead of replacing the mount entirely. Uncomment the second `volumes` line in `compose.yaml` and set the host path:

```yaml
volumes:
  - ./pictures:/usr/share/nginx/html/pictures
  - /path/to/your/existing/photos:/usr/share/nginx/html/pictures/external:ro
```

The read-only library then shows up in the slideshow like any other subfolder, merged into the same photo pool, but the inbox/HEIC feature can never write into it since that specific mount point is read-only.

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `PUID` | `1000` | Host user ID the container runs as. Should match whoever owns `pictures/` (check with `id -u`) |
| `PGID` | `1000` | Host group ID the container runs as. Should match whoever owns `pictures/` (check with `id -g`) |
| `INBOX_SCAN_SECONDS` | `30` | How often `pictures/_inbox/` is checked for newly dropped photos to convert/move/dedupe |
| `SERVER_SCAN_SECONDS` | `60` | How often the server rescans the `pictures/` folder and rewrites `photos.js` |
| `BROWSER_REFRESH_MINUTES` | `15` | How often the browser reloads the page to pick up new/removed photos |
| `SLIDESHOW_DELAY_SECONDS` | `10` | How many seconds each photo stays on screen before crossfading to the next |
| `SLIDESHOW_SHUFFLE` | `true` | `true` = random photo order, reshuffled each full cycle, guaranteed never to repeat the same photo twice in a row (unless only one photo exists); `false` = alphabetical path order (folders sort together, files uploaded later don't jump ahead of other folders) |

## How it works

- `Dockerfile` builds a custom image on top of `nginxinc/nginx-unprivileged:alpine`, with the slideshow page and a photo-scanning script baked in. The container starts as root only long enough to adjust its internal user to match `PUID`/`PGID`, then drops privileges permanently before running anything else
- On container start (and on a repeating interval), `generate-photos.sh` scans the mounted `pictures/` folder and writes out `photos.js`, a plain JS array of image paths
- Subfolders inside `pictures/` are scanned recursively, and merged into one flat pool (no per-folder grouping)
- Any folder named `ignore`, at any depth inside `pictures/` (e.g. `pictures/ignore/` or `pictures/vacation2026/ignore/`), is skipped entirely, so photos can be staged there without joining the rotation
- `index.html.template` is processed by nginx's built-in `envsubst` templating on startup, substituting environment variables into the page before serving it
- The page crossfades through photos on a timer, and periodically reloads itself in-browser to pick up newly added/removed photos
- Each photo is preloaded in the background before it's shown, and a photo that fails to load (e.g. corrupted mid-upload) is silently skipped in favor of the next one, so a bad file never gets displayed
- If `pictures/` has no usable photos, the page shows a simple "no photos found" message instead of a blank screen, whether that's true from the very first load or every photo gets removed while the page is already running
- The image includes a Docker `HEALTHCHECK`, so `docker ps` and tools like Portainer can tell if the web server has actually stopped responding, not just whether the container is still running
- Dropping a photo (including `.heic`/`.HEIC` straight from an iPhone) into `pictures/_inbox/` gets it converted if needed, moved into `pictures/` at the matching path, and removed from the inbox automatically: no conversion software needed. Duplicate content (the same photo dropped twice, even under a different filename) is detected by hash and silently skipped rather than shown twice; a name collision with an existing photo gets auto-renamed (`photo (1).jpg`) rather than overwriting the original

## Compatibility notes

- Tested working on iOS 9.3.5 Safari (iPad 3) and modern desktop browsers
- The photo scanner only picks up `.jpg`/`.jpeg`, `.png`, and `.gif` (including animated GIFs). All three have been supported since the earliest iOS releases, and are confirmed working on iOS 9.3.5 Safari
- `.webp` is deliberately excluded: Safari didn't add WebP support until Safari 14 / iOS 14
- `.bmp` is also excluded: it renders fine on modern desktop browsers, but was tested and does not render on iOS 9.3.5 Safari
- Photos only, video is not supported. `.mp4`/H.264 was tested and doesn't render reliably on iOS 9 Safari, since `playsinline` support wasn't added until iOS 10
- `.mov` files hit the same `playsinline` problem if they contain H.264, which is true of most consumer `.mov` exports; the blocker is the missing browser feature, not the container format
- `.webm` isn't supported at all: Safari has never had native WebM support
- HEVC/H.265 (in either container) fails even more fundamentally: iOS didn't add HEVC decoding until iOS 11, and only on A9-chip-or-later devices. The iPad 3's A5X chip predates that requirement entirely, so the codec itself can't be decoded, not just blocked by the `playsinline` issue
- The photo scanner doesn't pick up video files of any format regardless

## Companion tools

A file-manager container (e.g. [FileBrowser](https://github.com/gtsteffaniak/filebrowser) or [Dufs](https://github.com/sigoden/dufs)) pointed at the same `pictures/` folder is optional, not required: `pictures/_inbox/` (see Usage above) handles adding and converting photos on its own. A GUI file manager is only useful if you also want to browse, rename, or delete existing photos without direct filesystem/network access. Not included in this repo, deployed alongside it if wanted.
