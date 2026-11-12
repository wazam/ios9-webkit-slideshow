# Releasing

How a new version of iOS 9 WebKit Slideshow goes from `main` to published Docker images and a GitHub Release. Replace `X.Y.Z` with the new version throughout.

## 1. Choose the version

No file holds the app version. The git tag `vX.Y.Z` is the version: the Docker Publish workflow reads it to tag the images and to set the image's `org.opencontainers.image.version` label.

Follow [semver](https://semver.org/). While the slideshow is on `0.x`, bump the minor version (`0.Y.0`) for any change that requires existing users to edit their `compose.yaml`, `.env`, or `pictures` folder, and the patch version (`0.Y.Z`) for everything else.

### If the release changes the base image

The only pinned dependency is the nginx line in the [`Dockerfile`](Dockerfile)'s `FROM nginxinc/nginx-unprivileged:1.N-alpine`. Patch updates within that line arrive when the base image is republished, and Alpine package updates with every build, since the Dockerfile runs `apk upgrade`. Move to a new line on purpose only: for a security fix, or when the current line reaches end of life. Change the `org.opencontainers.image.base.name` label to match `FROM`, then retest everything in step 3, the iPad included.

## 2. Write the release notes in CHANGELOG.md

Notes collect under `## Unreleased` at the top of [CHANGELOG.md](CHANGELOG.md) as changes land on `main`. Rename that heading to the new version, and go over its notes against the rules below. If there's no Unreleased section, add the version's section at the top, under the intro paragraph:

```markdown
## [vX.Y.Z](https://github.com/wazam/ios9-webkit-slideshow/releases/tag/vX.Y.Z) (YYYY-MM-DD)

### Upgrading

- ...

### What's New

- ...

### Bug Fixes

- ...
```

- Use the date the release goes live, in local time (America/New_York).
- Leave out any section with nothing in it.
- The heading link stays broken until the GitHub Release exists in step 7.
- After the release, start a new empty `## Unreleased` section only when the next change lands, so the top of the file never shows an empty heading.

Writing rules:

- Write the notes fresh for people running the slideshow. Never copy commit messages. Group changes by what users will notice, put the most significant first, and use plain language instead of commit-speak.
- Call out anything users must do when upgrading (a renamed or removed setting, a change to the `pictures` folder's ownership, a new compose file) under `### Upgrading`, which always comes first. Say what to do, not just what changed, and name both the old and new values.
- This section is the only source of the notes. The GitHub Release in step 7 is copied from it, so make any wording changes here first.

## 3. Test the commit locally

Build fresh and start the stack:

```bash
docker compose build --pull --no-cache && docker compose up -d
```

Inside the repo, `docker compose` also loads `compose.override.yaml`, so this runs the local build, not the published image. Then:

- If a `--pull --no-cache` build ran the night before and you left those flags off to reuse its layers, check that nothing is left to upgrade: `docker run --rm --entrypoint sh -u root ios9-webkit-slideshow:local -c 'apk update -q >/dev/null 2>&1; apk list -u 2>/dev/null | wc -l'` prints `0`; otherwise rebuild with the flags.
- `docker inspect -f '{{.State.Health.Status}}' slideshow` says `healthy`, and `docker logs --tail 20 slideshow` shows nginx starting with no errors.
- `docker logs slideshow 2>&1 | grep '^process-inbox:'` prints nothing. A line there means the container can't write `pictures/`, and it names the folder's owner and the fix.
- [http://localhost:8080/](http://localhost:8080/) shows the slideshow.
- A HEIC photo dropped into `pictures/_inbox/` shows up converted in `pictures/` within `INBOX_SCAN_SECONDS`.
- The iPad shows the slideshow from this machine's LAN address. A modern desktop browser isn't a substitute: iOS 9 Safari is the target.

**What ships isn't exactly what was tested.** Docker Publish builds the images again after the tag is pushed. The base image can move to a newer patch within its nginx line, and every Alpine package (`apk upgrade`, then `libheif-tools`) to newer versions, between the local build, Compose Test and the publish. The GHCR and Docker Hub images are also separate builds. The published-image test in step 6 runs both registries' images on amd64 and arm64 right after publishing, which is the closest check.

## 4. Commit and tag

Commit the release, including `CHANGELOG.md` so the tagged commit carries its own notes. A release commit that bundles unrelated changes gets one prefixed line per change:

```bash
git add CHANGELOG.md <other changed files>
git commit -m "release: vX.Y.Z" -m "feat: ..." -m "fix: ..."
git tag -a vX.Y.Z -m "vX.Y.Z"
```

The tag is annotated, so it records who tagged the release and when, and `git describe` finds it.

## 5. Push `main`, wait for CI, then push the tag

Pushing the tag starts the Docker Publish workflow ([`.github/workflows/docker.yml`](.github/workflows/docker.yml)) right away, and it doesn't wait for any other workflow. So push `main` on its own first, and push the tag only once Compose Test passes on the release commit:

```bash
git push origin main
sleep 15  # give GitHub a moment to queue the run
gh run watch --exit-status "$(gh run list --workflow compose-test.yml --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId -q '.[0].databaseId')"
git push origin vX.Y.Z
git ls-remote --tags origin | grep vX.Y.Z
git remote -v  # SSH only, no token in any URL
```

If Compose Test fails, fix the cause, commit it, move the tag to the new commit (`git tag -fa vX.Y.Z -m "vX.Y.Z"`), and repeat this step.

Push one tag at a time. Tags pushed together publish in parallel, and `latest` can end up on whichever finishes last.

## 6. Watch the images publish, then the published-image test

Docker Publish builds the image for `linux/amd64` and `linux/arm64`, and pushes it to both registries with a GitHub build provenance attestation for each:

- `ghcr.io/wazam/ios9-webkit-slideshow`
- `wazam123/ios9-webkit-slideshow` on Docker Hub

Each gets four tags: `X.Y.Z`, `X.Y`, `latest`, and `main`. Follow the run until both jobs pass:

```bash
sleep 15  # give GitHub a moment to queue the run
gh run watch --exit-status "$(gh run list --workflow docker.yml --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId -q '.[0].databaseId')"
```

If a job fails, fix the cause on `main`, then move the tag to the fixed commit before rerunning (`git tag -fa vX.Y.Z -m "vX.Y.Z"` and `git push -f origin vX.Y.Z`), so the images and the tag match.

When Docker Publish succeeds, it starts one Compose Test run with four jobs: it pulls `X.Y.Z` from GHCR and from Docker Hub, on amd64 and on arm64, and runs the same checks as on every push. All four must pass:

```bash
sleep 15  # give GitHub a moment to queue the run
gh run watch --exit-status "$(gh run list --workflow compose-test.yml --event workflow_run --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId -q '.[0].databaseId')"
```

The commit filter works because `main` and the tag point at the same commit; push nothing else to `main` until this run finishes. If no run appears, check that `gh workflow list` shows Compose Test as active: GitHub disables scheduled workflows after 60 days without repo activity, and a disabled workflow skips this run too (`gh workflow enable compose-test.yml`).

### If the published image is bad

Point `latest` back at the previous version's images, which are already built, then fix forward with a new patch version instead of re-pushing the tag:

```bash
docker buildx imagetools create -t ghcr.io/wazam/ios9-webkit-slideshow:latest ghcr.io/wazam/ios9-webkit-slideshow:<previous>
docker buildx imagetools create -t wazam123/ios9-webkit-slideshow:latest wazam123/ios9-webkit-slideshow:<previous>
```

Do the same for `main`, and for `X.Y` if it moved.

## 7. Create the GitHub Release

Pull the notes for this version out of `CHANGELOG.md`, without its `##` line, and create the release from them:

```bash
awk '/^## \[vX.Y.Z\]/{f=1;next} /^## /{f=0} f' CHANGELOG.md \
  | gh release create vX.Y.Z --title "vX.Y.Z" --latest --notes-file -
```

Then check that every older release page still matches its `CHANGELOG.md` section. Pages edited on GitHub drift:

```bash
for v in $(git tag -l 'v*'); do
  diff <(gh release view $v --json body -q .body | tr -d '\r' | sed '/^$/d') \
       <(awk "/^## \\[$v\\]/{f=1;next} /^## /{f=0} f" CHANGELOG.md | sed '/^$/d') >/dev/null \
    && echo "$v matches" || echo "$v DIFFERS"
done
```

For a page that differs, move anything it has that `CHANGELOG.md` lacks into `CHANGELOG.md` first (commit it as `docs: sync vX.Y.Z notes with its release page`), then overwrite the page from it:

```bash
awk "/^## \\[$v\\]/{f=1;next} /^## /{f=0} f" CHANGELOG.md | gh release edit $v --notes-file -
```

## 8. Check the published image

```bash
docker buildx imagetools inspect ghcr.io/wazam/ios9-webkit-slideshow:X.Y.Z   # linux/amd64 and linux/arm64, nothing else
docker buildx imagetools inspect wazam123/ios9-webkit-slideshow:X.Y.Z        # the same
for image in ghcr.io/wazam/ios9-webkit-slideshow:X.Y.Z wazam123/ios9-webkit-slideshow:X.Y.Z; do
  gh attestation verify oci://$image --repo wazam/ios9-webkit-slideshow \
    --signer-workflow wazam/ios9-webkit-slideshow/.github/workflows/docker.yml --source-ref refs/tags/vX.Y.Z
done
```

Both registries should list only `linux/amd64` and `linux/arm64`, and both attestations should verify.

`docker.yml` attests each pushed image with `actions/attest` (since v0.2.0). The attestations live in GitHub's attestation store, not in the registries, and both build steps set `provenance: false`, so buildx adds no unsigned provenance manifests (`unknown/unknown`) to the index. Each release therefore adds only its image to GHCR, and the package page's header shows it. v0.1.0 was signed with cosign instead and has no attestation: its signature, pushed last as a `sha256-<digest>.sig` tag in the image's package, became the version the page showed. That signature was deleted from the package on 2026-11-11, so v0.1.0 can't be checked with `cosign verify` either (its entries in Sigstore's transparency log remain).

Then the labels and the description annotation, in both registries. This repo has no `.tool-versions`, so the commands use the system Python, `/usr/bin/python3`:

```bash
for image in ghcr.io/wazam/ios9-webkit-slideshow:X.Y.Z wazam123/ios9-webkit-slideshow:X.Y.Z; do
  docker buildx imagetools inspect $image --format '{{json .Image}}' | /usr/bin/python3 -c "import json,sys; d=json.load(sys.stdin); [print(p, len(v['config']['Labels']), json.dumps(v['config']['Labels'], indent=1, sort_keys=True)) for p, v in d.items()]"
  docker buildx imagetools inspect $image --raw | /usr/bin/python3 -c "import json,sys; print(json.load(sys.stdin).get('annotations'))"
done
git rev-parse 'vX.Y.Z^{commit}'
```

- Both platforms show the same 13 labels: the Dockerfile's fixed ones (title `iOS 9 WebKit Slideshow`, the one-line description, this repo's `url`, `source` and `documentation`, `licenses`, `authors`, `vendor`, `base.name` and `maintainer`), plus `created`, `revision` equal to the `git rev-parse` output, and `version` `X.Y.Z`. The Dockerfile sets `maintainer` and empty `version`, `revision` and `created` so none of the nginx base image's own labels show through.
- The index annotation holds the description, and the [GHCR package page](https://github.com/wazam/ios9-webkit-slideshow/pkgs/container/ios9-webkit-slideshow)'s header shows the `X.Y.Z` image, not a `sha256-...sig` tag, with the description and a `docker pull` command for the image.

### GHCR package versions

GHCR lists every manifest as a version. A release adds three: its tagged index and, untagged, the amd64 and arm64 images the index lists. v0.1.0 also has two untagged `unknown/unknown` provenance manifests. Never delete an untagged version that a tagged index lists: pulls of that release, or tools that read the whole index, break. Docker Hub's Image Management page lists the same manifests under the same rule, and its deletions can't be undone. To see what each version is:

```bash
gh api --paginate '/users/wazam/packages/container/ios9-webkit-slideshow/versions?per_page=100' \
  --jq '.[] | "\(.id) \(.name) \(.metadata.container.tags|join(","))"'
docker buildx imagetools inspect --raw ghcr.io/wazam/ios9-webkit-slideshow:X.Y.Z   # the digests the index lists
```

Listing needs a token with `read:packages`, and deleting one needs `delete:packages` (`gh auth refresh -h github.com -s read:packages,delete:packages`, then `-r` to drop them). GitHub can restore a deleted version for 30 days.

## 9. Update the Docker Hub page and GitHub About

GHCR's package page shows the README by itself. Docker Hub's page and GitHub's About description don't update on their own, so copy them from the README whenever its intro, Quick Start, Features or Contributing section changed:

- **Docker Hub overview:** on hub.docker.com, open the repository's General tab and replace the overview with the output of the command below, which builds it from `README.md` and `compose.yaml` so the page can't drift from them. In order, it has:
    - a first line `GitHub: https://github.com/wazam/ios9-webkit-slideshow`, then the README's intro paragraph without its icon
    - `## Quick Start`: the two registries, `compose.yaml` itself with its `image:` line changed to `wazam123/ios9-webkit-slideshow:latest` (the page is Docker Hub's), the settings and folder-owner paragraphs, and the numbered steps without the tip box or Build from Source; after the download step, a note that the downloaded file pulls from GHCR and how to switch it
    - `## Features`, and `## Issues and Feature Requests` with the sentence from the README's Contributing section

    Every link is absolute; the Environment Variables link points to the README on GitHub. Then check the public page, [hub.docker.com/r/wazam123/ios9-webkit-slideshow](https://hub.docker.com/r/wazam123/ios9-webkit-slideshow).

```bash
# Run from the repo root. Append | /mnt/c/Windows/System32/clip.exe to copy it to the Windows clipboard
/usr/bin/python3 -I - <<'EOF'
import re
s = open('README.md').read()
def sec(a, b):
    i = s.index(a); return s[i:s.index(b, i)].rstrip() + '\n'
base = 'https://github.com/wazam/ios9-webkit-slideshow'
ghcr, hub = 'ghcr.io/wazam/ios9-webkit-slideshow:latest', 'wazam123/ios9-webkit-slideshow:latest'
intro = re.sub(r'^<img[^>]*> ', '', next(l for l in s.split('\n') if l.startswith('<img src="apple-touch-icon.png"')))
compose = open('compose.yaml').read()
assert compose.count(ghcr) == 1
compose = compose.replace(ghcr, hub)
setup = re.search(r'^\*\*Required setup:\*\* the (.*)$', s, re.M).group(1)
steps = sec('1. **Create the pictures directory**', '### Build from Source')
dl_end = '/main/compose.yaml\n   ```\n'
assert steps.count(dl_end) == 1
steps = steps[:steps.index(dl_end) + len(dl_end)] + steps[steps.index('3. **Start the stack**') - 1:]
steps = steps.replace(dl_end, dl_end + '\n   The downloaded `compose.yaml` pulls from GHCR. To pull from Docker Hub instead, change its `image:` line to `' + hub + '`, as above.\n')
quick = '\n'.join([
    '## Quick Start', '',
    'The image is published to [GitHub Container Registry](https://github.com/wazam/ios9-webkit-slideshow/pkgs/container/ios9-webkit-slideshow) (`ghcr.io/wazam/ios9-webkit-slideshow`) and Docker Hub (`wazam123/ios9-webkit-slideshow`). This is the `compose.yaml` to use, pulling from Docker Hub:', '',
    '```yaml', compose.rstrip(), '```', '',
    f'Every setting is optional: it reads from a `.env` file next to `compose.yaml` and falls back to the defaults shown. The README\'s [Environment Variables]({base}#environment-variables) table describes each one.', '',
    'The ' + setup, '',
    steps])
feat = sec('## Features', '## Tech Stack')
issues = sec('## Contributing', '## License').replace('## Contributing', '## Issues and Feature Requests')
issues = issues.replace('](CHANGELOG.md)', f']({base}/blob/main/CHANGELOG.md)')
issues = issues.replace('](ROADMAP.md)', f']({base}/blob/main/ROADMAP.md)')
print('\n'.join([f'GitHub: {base}', '', intro, '', quick, feat, issues]).rstrip())
EOF
```

An `AssertionError` means the README's download step or `compose.yaml`'s `image:` line changed shape; update the command to match before pasting anything.

- **One-line description:** one sentence of at most 100 characters (Docker Hub's limit) saying what the README's first sentence says. Its one copy in the repo is the Dockerfile's `org.opencontainers.image.description` label, which Docker Publish also puts on GHCR's package page. Change it there first, then copy it to GitHub's About description and Docker Hub's short description:

    ```bash
    desc=$(sed -n 's/.*org\.opencontainers\.image\.description="\([^"]*\)".*/\1/p' Dockerfile)
    printf '%s\n%s characters\n' "$desc" "$(printf '%s' "$desc" | wc -m)"
    gh repo edit wazam/ios9-webkit-slideshow --description "$desc"
    ```

    Paste the same sentence into Docker Hub's short description on the General tab.

## 10. Verify

- [ ] The slideshow runs from the published image: healthy, logs normal, photos show on the iPad, and the inbox converts a HEIC photo.
- [ ] The [release](https://github.com/wazam/ios9-webkit-slideshow/releases) shows as Latest with the notes from step 2, and the `CHANGELOG.md` heading link now opens it.
- [ ] The loop in step 7 prints `matches` for every tag.
- [ ] The README's badges show the new version, and its compose example, setup steps, and demo still match the release.
- [ ] The Docker Hub page and the About description match the README.
