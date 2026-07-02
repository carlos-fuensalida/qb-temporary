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
  -v "$PWD/downloads:/config/Downloads:rw" \
  qbt-kiosk
```

> For a real deployment, swap `$PWD/downloads` for the shared/network path,
> e.g. `-v /files/shared/drive:/config/Downloads:rw`.

### Option B — run a prebuilt image from the registry

```bash
docker run -d \
  --name=qb-staging-container \
  --shm-size 2g \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -p 4443:4443 \
  -v /files/shared/drive:/config/Downloads:rw \
  qbtcontainers.azurecr.io/qbtstagingcontainer:latest
```

### Option C — docker compose

Edit the download path in [docker-compose.yml](docker-compose.yml) if needed, then:

```bash
docker compose up -d --build
```

### Option D — plain `docker run`, matching docker-compose.yml

Equivalent to Option C, if you'd rather not use compose:

```bash
docker build -t qbt-kiosk:latest .

docker run -d \
  --name=qb \
  --restart=unless-stopped \
  -p 4443:4443 \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -e WEB_LISTENING_PORT=4443 \
  -v /files/shared/drive:/config/Downloads:rw \
  qbt-kiosk:latest
```

Or, using the prebuilt registry image instead of building locally:

```bash
docker run -d \
  --name=qb \
  --restart=unless-stopped \
  -p 4443:4443 \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -e WEB_LISTENING_PORT=4443 \
  -v /files/shared/drive:/config/Downloads:rw \
  qbtcontainers.azurecr.io/qbtstagingcontainer:latest
```

---

## Open the app

Browse to:

```
http://<host-ip>:4443
```

(on the same machine: <http://localhost:4443>)

You'll land on Query Builder in a normal Chromium window.

---

## What the flags mean

| Flag | Purpose |
|------|---------|
| `--shm-size 2g` | Prevents Chromium crashes on heavy pages. |
| `-e USER_ID` / `-e GROUP_ID` | Owner uid/gid of the container and of downloaded files — match them to the account/group that owns the host download folder. |
| `-p 4443:4443` | Exposes the web GUI on host port 4443. |
| `-v <host>:/config/Downloads:rw` | Where downloaded files land on the host (note the capital **D**). |

> **No `--cap-add=SYS_ADMIN` needed.** This image runs Chromium with
> `--no-sandbox`, so the capability would do nothing. The base image has no env
> var to append custom Chromium flags, so
> [root/etc/services.d/app/params](root/etc/services.d/app/params) overrides the
> app service's arg list to add `--test-type` alongside `--no-sandbox`, which
> suppresses the "unsupported command-line flag" warning banner. (The sandbox
> stays off — an accepted trade-off for this URL-locked internal kiosk.)

---

## Downloads & permissions

Chromium creates downloads as `0600` (owner-only). A small built-in service
(`fix-downloads`) automatically relaxes new files to `666` (and folders to
`777`) so other users and groups on the host can read and write them.

To confirm it's running:

```bash
docker logs qb 2>&1 | grep fix-downloads      # expect: [fix-downloads] started...
```

Downloaded files should show as `-rw-rw-rw-`. To make them group-scoped instead
of world-open, change `FILE_MODE`/`DIR_MODE` in
[root/etc/services.d/fix-downloads/run](root/etc/services.d/fix-downloads/run)
to `664`/`775` and rebuild.

---

## Change the URL / allow another domain

[policy.json](policy.json) is the single place to edit:

1. Add the host to `URLAllowlist`.
2. If it's the new landing page, update `HomepageLocation` and
   `RestoreOnStartupURLs`.
3. Rebuild the image.

`URLAllowlist` entries match the host **and its subdomains**.

---

## Verify the lockdown

Inside the browser session, open `chrome://policy`. Confirm `URLBlocklist`,
`URLAllowlist`, `HomepageLocation`, and `ShowHomeButton` are listed with
**Status: OK**. Then try navigating somewhere off-list (e.g. `example.com`) — it
should show a **blocked** page.

> If a login flow stalls, it's likely hitting a redirect host not in the
> allowlist (federated logins often bounce through extra domains). Note the
> blocked host, add it to `URLAllowlist`, and rebuild.

---

## Manage the container

```bash
docker logs -f qb            # follow logs
docker stop qb               # stop
docker start qb              # start again
docker rm -f qb              # remove
# with compose:
docker compose down
```
