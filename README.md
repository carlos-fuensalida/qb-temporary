# QB Container — Query Builder browser

A dedicated Chromium browser, delivered as a Docker container, that opens
**Query Builder** and is locked to it. Users access it through their own web
browser (via the built-in noVNC web layer) — nothing to install on the client.

- **Normal browser window** — toolbar, Home button, back/forward, reload — so a
  user who gets stuck can recover without restarting the container.
- **Locked down** to Query Builder + its allowed SSO/login domains via a
  Chromium managed policy ([policy.json](policy.json)). Any other URL is blocked.
- **Downloads** are saved to a mounted folder and made readable/writable to
  other users and groups automatically.

Target site: `https://qbt-staging.fdsaservices.com/qbt/`

---

## Prerequisites

- Docker installed and running.
- A host folder to receive downloads (e.g. a shared/network drive).

---

## Start the app

### Option A — build and run locally

```bash
# 1. Build the image (run from this directory)
docker build -t qbt-kiosk .

# 2. Start the container (downloads land in ./downloads for local testing)
mkdir -p downloads
docker run -d \
  --name=qb \
  --shm-size 2g \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -p 4443:4443 \
  -v "$PWD/downloads:/downloads:rw" \
  qbt-kiosk
```

> For a real deployment, swap `$PWD/downloads` for the shared/network path,
> e.g. `-v /files/shared/drive:/downloads:rw`.

### Option B — run a prebuilt image from the registry

```bash
docker run -d \
  --name=qb \
  --shm-size 2g \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -p 4443:4443 \
  -v /files/shared/drive:/downloads:rw \
  qbtcontainers.azurecr.io/qbtstagingcontainer:latest
```

### Option C — plain `docker run` with `--restart=unless-stopped`

```bash
docker build -t qbt-kiosk:latest .

docker run -d \
  --name=qb \
  --restart=unless-stopped \
  -p 4443:4443 \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -v /files/shared/drive:/downloads:rw \
  qbt-kiosk:latest
```

Or, using the prebuilt registry image instead of building locally:

```bash
docker run -d \
  --name=qb \
  --restart=unless-stopped \
  -p 4443:4443 \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -v /files/shared/drive:/downloads:rw \
  qbtcontainers.azurecr.io/qbtstagingcontainer:latest
```

> **Note:** the downloads volume mounts at `/downloads`, not `/config/Downloads`.
> It's kept outside `/config` on purpose — see
> [Why downloads live outside `/config`](#why-downloads-live-outside-config) —
> so update any existing pod/volume specs accordingly when upgrading.

---

## Open the app

Browse to:

```
http://<host-ip>:4443
```

(on the same machine: <http://localhost:4443>)

You'll land on Query Builder in a normal Chromium window.


---

## Change the URL / allow another domain

[policy.json](policy.json) is the single place to edit:

1. Add the host to `URLAllowlist`.
2. If it's the new landing page, update `HomepageLocation` and
   `RestoreOnStartupURLs`.
3. Rebuild the image.

`URLAllowlist` entries match the host **and its subdomains**.

---

## Why downloads live outside `/config`

The downloads volume mounts at `/downloads`, not `/config/Downloads`, and
Chromium is pointed at it via the `DownloadDirectory` policy in
[policy.json](policy.json).

This matters because the base image (`jlesage/chromium`) recursively `chown`s
the entire `/config` tree to `USER_ID`/`GROUP_ID` on **every** container
start, not just the first one. That's fine when `/config` is local disk, but
if the mounted downloads folder is a network share (e.g. an Azure Files/CIFS
mount, as used by the AKS automation workspaces), a recursive chown over the
network turns into a per-file round trip — adding minutes to startup, and
getting slower as the share fills up. Keeping the network mount outside
`/config` means that chown only ever walks local disk, so startup stays fast
regardless of how much is in the downloads share.

Do **not** "fix" this by setting `TAKE_CONFIG_OWNERSHIP=0` — that disables
the chown for local `/config` paths too (`xdg`, `log`, the Chromium profile),
which need it and aren't covered by any volume's own uid/gid mount options,
and causes a permission-denied crash loop instead.

---

## HOW TO: Build, tag, and push a release image

The registry (`qbtcontainers.azurecr.io`) hosts separate staging and prod
images. Before building, set the target URL in **both** of these files:

- [policy.json](policy.json) — `HomepageLocation` and `RestoreOnStartupURLs`.
- [root/defaults/Bookmarks](root/defaults/Bookmarks) — the `url` field of the
  "Query Builder" bookmark.

### Staging

URL: `https://qbt-staging.fdsaservices.com/qbt/`

```bash
docker login -u read-write -p <password> qbtcontainers.azurecr.io

docker build -t qbt-kiosk:latest .
docker tag qbt-kiosk:latest qbtcontainers.azurecr.io/qbtstagingcontainer:latest
docker push qbtcontainers.azurecr.io/qbtstagingcontainer:latest
```

### Prod

Set the URL in both files above to
`https://fdsa-query-builder.alzheimersdata.org/qbt/`, then run the same
commands against the prod image name:

```bash
docker login -u read-write -p <password> qbtcontainers.azurecr.io

docker build -t qbt-kiosk:latest .
docker tag qbt-kiosk:latest qbtcontainers.azurecr.io/qbtcontainer:latest
docker push qbtcontainers.azurecr.io/qbtcontainer:latest
```

