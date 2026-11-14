# Changelog

Release notes for every version, newest first. Each version is tagged in git and has a matching [release on GitHub](https://github.com/wazam/ios9-webkit-slideshow/releases). Changes that haven't been released yet collect under **Unreleased**, and [RELEASING.md](RELEASING.md) covers how to ship them.

## Unreleased

### What's New

- A `TZ` setting sets the time zone of the timestamps in `docker logs`, for example `TZ=America/New_York`. It defaults to UTC, as before. Copy the new `compose.yaml` to use it.
- `compose.yaml` is simpler: it no longer includes the hardening block, and each setting is marked `# optional`. An existing `compose.yaml` keeps working.
- Reverse proxy support: set `FORWARDED_ALLOW_IPS` to your proxy's IP, and the access log shows each visitor's real IP instead of the proxy's. Only requests from the addresses you list can set `X-Forwarded-For`, so nobody else can fake their IP. It defaults to `127.0.0.1,::1`.
- `.env.example` is gone. The README's Environment Variables table describes every setting and its default, and `compose.yaml` marks each one `# optional` or `# required`. Put the ones you set in `.env` next to `compose.yaml`, one `NAME=value` per line.

## [v0.2.0](https://github.com/wazam/ios9-webkit-slideshow/releases/tag/v0.2.0) (2026-11-11)

### Upgrading

- The container always runs as uid 1000 and no longer reads `PUID` or `PGID`, so remove them from your compose file. Give your pictures folder to uid 1000 (`sudo chown -R 1000:1000 ./pictures`), or, if the folder's owner isn't root, set `user:` in your compose file to that owner (from `ls -nd ./pictures`). A folder owned by root always needs the chown.
- Two settings are renamed: `SERVER_SCAN_SECONDS` to `PICTURES_SCAN_SECONDS`, and `SLIDESHOW_DELAY_SECONDS` to `SLIDESHOW_INTERVAL_SECONDS`. If you set either one, change it to the new name; the old names are ignored.
- The compose service is renamed from `app` to `slideshow`. Run `docker compose down` with your current compose file before you replace it. Otherwise `docker compose up -d` fails, because the old container still holds the name `slideshow`. If you have your own override file, rename `app:` in it too.

### What's New

- `compose.yaml` adds container hardening: a read-only filesystem, no new privileges, all capabilities dropped, and memory and process limits. Copy the new file to get it.
- The image is built on nginx 1.31 instead of whatever version the base image's `alpine` tag points to.
- `compose.yaml` reads every setting from a `.env` file next to it, with the defaults written in, and `.env.example` lists them all.
- Images on both GHCR and Docker Hub carry a GitHub build provenance attestation, recording the repository, workflow, tag and commit that built them, in place of the cosign signature only GHCR's images had. To check one: `gh attestation verify oci://ghcr.io/wazam/ios9-webkit-slideshow:<version> --repo wazam/ios9-webkit-slideshow`. Each image index now lists only the amd64 and arm64 images, without buildx's unsigned `unknown/unknown` provenance entries.
- A new app icon, shown in the browser tab and on the iPad's home screen. To see it on a home screen bookmark made with 0.1.0, delete the bookmark and add it again, since iOS keeps the icon it saved.

### Bug Fixes

- Nothing in the container runs as root. Before, the process that copied nginx's logs to `docker logs` did, and it could be pointed at files only root can read.
- Photos and folders the inbox creates are no longer writable by every user on the host.
- If the container can't write to the pictures folder, `docker logs` now says so once at startup, with the command that fixes it, instead of the inbox staying off without a word. A folder mounted read-only on purpose still logs nothing.
- The image includes Alpine's current security updates, including fixes for brotli, expat, musl and zlib that the nginx base image doesn't have yet, and no longer includes curl, which nothing in the image uses.
- The image's labels give the app's name, description and project link. 0.1.0's had the repository name, an empty description, and nginx's project link.
- GHCR's package page shows the image, with its description and a `docker pull` command for it. 0.1.0's page showed the cosign signature instead, which was stored as a tag in the same package and, pushed last, became the version the page showed.

## [v0.1.0](https://github.com/wazam/ios9-webkit-slideshow/releases/tag/v0.1.0) (2026-09-17)

### What's New

- A crossfading photo slideshow for old hardware, developed for and tested on an iPad 3 running iOS 9.3.6 Safari. It works in modern browsers too.
- Shows JPG, PNG and GIF photos, animated GIFs included. WebP, BMP and video are left out, since none of them render reliably, or at all, on iOS 9 Safari.
- A photo that fails to load is skipped instead of showing a broken image. If no photo can be shown, from the first load or later while the page is open, the display shows a "no photos found" message instead of a black screen.
- Photos play in shuffled order (the default) or alphabetically, and any folder named `ignore` is left out of the rotation.
- Photos added to the `pictures/` folder show up without a restart. Settings control how long each photo stays on screen and how often the server and the browser check for new photos.
- Photos dropped into `pictures/_inbox/` are moved into place automatically, and HEIC photos from an iPhone are converted to JPEG on the way, with no conversion software needed.
- The same photo dropped twice, even under a different name, is only added once. A different photo with a name already in use gets a numbered name instead of replacing the existing one.
- An existing photo library can be mounted read-only, either in place of the `pictures/` folder or alongside it.
- `PUID` and `PGID` match the container to the owner of the `pictures/` folder, so files either side creates stay usable by both.
- Published to GitHub Container Registry and Docker Hub for amd64 and arm64, with a Docker healthcheck so monitoring tools can tell when the web server stops responding.
