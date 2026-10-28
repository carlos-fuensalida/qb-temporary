# QB Container — aha (production)

A dedicated Chromium browser, delivered as a Docker container, that opens
**Query Builder** and is locked to it. Users access it through their own web
browser (via the built-in noVNC web layer) — nothing to install on the client.

- **Normal browser window** — toolbar, Home button, back/forward, reload — so a
  user who gets stuck can recover without restarting the container.
- **Locked down** to Query Builder + its allowed SSO/login domains via a
  Chromium managed policy ([policy.json](policy.json)). Any other URL is blocked.
- **Downloads** are saved to a mounted folder and made readable/writable to
  other users and groups automatically.

Target site: `https://fdsa-query-builder.alzheimersdata.org/qbt/`

This is the **aha** flavor: the permissions/AKS-mount fixes (see
[Why downloads live outside `/config`](#why-downloads-live-outside-config)),
distributed to our own registry and mirrored to AHA's own registry
(Aridhia). It does **not** carry the `grip-*` branches' separate
downloads-location/File-System-Access fix — `aha-*` and `grip-*` are
different fixes for different environments, not the same code. See `main`'s
README for the full branch map.

---

## Prerequisites

- Docker installed and running.
- A host folder to receive downloads (e.g. a shared/network drive).

---

## Start the app

### Option A — build and run locally

```bash
docker build -t qbt-kiosk .

mkdir -p downloads
docker run -d \
  --name=qb \
  --shm-size 2g \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -p 4443:4443 \
  -v "$PWD/downloads:/downloads:rw" \
  qbt-kiosk
```

### Option B — run the published image

```bash
docker run -d \
  --name=qb \
  --shm-size 2g \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -p 4443:4443 \
  -v /files/shared/drive:/downloads:rw \
  qbtcontainers.azurecr.io/qbtcontainer:aha
```

> **Note:** the downloads volume mounts at `/downloads`, not
> `/config/Downloads` — see [Why downloads live outside `/config`](#why-downloads-live-outside-config).

---

## Open the app

Browse to `http://<host-ip>:4443` (or `http://localhost:4443` on the same
machine). You'll land on Query Builder in a normal Chromium window.

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

The base image (`jlesage/chromium`) recursively `chown`s the entire
`/config` tree to `USER_ID`/`GROUP_ID` on **every** container start. When the
mounted downloads folder is a network share (e.g. an Azure Files/CIFS mount,
as used by the AKS automation workspaces), that recursive chown turns into a
per-file network round trip — adding minutes to startup, and getting slower
as the share fills up. Keeping the network mount outside `/config` means the
chown only ever walks local disk, so startup stays fast regardless of how
much is in the downloads share. Full write-up, written for this production
rollout: [README-PROD.md](README-PROD.md).

Do **not** "fix" this by setting `TAKE_CONFIG_OWNERSHIP=0` — that disables
the chown for local `/config` paths too (`xdg`, `log`, the Chromium
profile), which need it, and causes a permission-denied crash loop instead.

---

## Build, tag, and push

URL: `https://fdsa-query-builder.alzheimersdata.org/qbt/` (already set in
this branch's `policy.json` and `root/defaults/Bookmarks`).

### Our registry

```bash
docker login -u read-write -p <password> qbtcontainers.azurecr.io

docker build -t qbt-kiosk:latest .
docker tag qbt-kiosk:latest qbtcontainers.azurecr.io/qbtcontainer:aha
docker push qbtcontainers.azurecr.io/qbtcontainer:aha
```

### AHA's registry (Aridhia)

```bash
docker login -u read-write -p <SOURCE_REGISTRY_PASSWORD> qbtcontainers.azurecr.io
docker pull qbtcontainers.azurecr.io/qbtcontainer:aha
docker tag qbtcontainers.azurecr.io/qbtcontainer:aha acrwesteuropeaddi.azurecr.io/0a6ed49f-321c-4320-b746-6b72de4f2640/fdsa_qbt:latest
docker login -u fdsa-qbt -p <TARGET_REGISTRY_PASSWORD> acrwesteuropeaddi.azurecr.io
docker push acrwesteuropeaddi.azurecr.io/0a6ed49f-321c-4320-b746-6b72de4f2640/fdsa_qbt:latest
```

> The Aridhia prod path (`fdsa_qbt`, no `_staging` suffix) mirrors the
> naming convention documented for staging — confirm against Aridhia's own
> records if this hasn't been pushed before.
