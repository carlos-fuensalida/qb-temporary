# Query Builder Container — AHA Staging

A Chromium browser in a Docker container that opens **Query Builder**
(`https://qbt-staging.fdsaservices.com/qbt/`) and is locked to it. Users reach it from their own web browser
(noVNC, port 4443) — nothing is installed on their machine. Downloads and
uploads use a shared drive mounted into the container.

| | |
|---|---|
| Image | `qbtcontainers.azurecr.io/qbtstagingcontaineraha:latest` |
| Target site | `https://qbt-staging.fdsaservices.com/qbt/` |
| Web port | `4443` |
| Bookmark shown in the browser | `Query Builder v6 (staging)` |

- **Normal browser window** — toolbar, Home button, back/forward, reload — so a
  user who gets stuck can recover without restarting the container.
- **Locked down** to Query Builder and its allowed login (SSO) domains by a
  Chromium managed policy ([`policy.json`](policy.json)). Any other URL is blocked.
- **Downloads** go to the mounted shared drive and are made readable and
  writable for other users and groups automatically.

---

## Quick start

```bash
docker run -d \
  --name=qb \
  --restart=unless-stopped \
  --shm-size 2g \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -p 4443:4443 \
  -v /mnt/vm-shared-storage:/downloads:rw \
  qbtcontainers.azurecr.io/qbtstagingcontaineraha:latest
```

Then open `http://<host-ip>:4443`. You land on Query Builder in a Chromium window.

The shared drive is mounted at `/downloads` (outside `/config`, see [Why outside `/config`](#why-the-default-is-outside-config)).

### Same thing with Docker Compose

```yaml
services:
  qb:
    image: qbtcontainers.azurecr.io/qbtstagingcontaineraha:latest
    container_name: qb
    restart: unless-stopped
    shm_size: 2gb
    environment:
      USER_ID: "10001"
      GROUP_ID: "1001"
    ports:
      - "4443:4443"
    volumes:
      - /mnt/vm-shared-storage:/downloads:rw
```

## Examples with `QB_DOWNLOAD_DIR`

`QB_DOWNLOAD_DIR` and the container side of `-v` must always be the same path.

**1. Default location, set explicitly** (shared drive at `/downloads`, outside `/config`):

```bash
docker run -d \
  --name=qb \
  --restart=unless-stopped \
  --shm-size 2g \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -e QB_DOWNLOAD_DIR=/downloads \
  -p 4443:4443 \
  -v /mnt/vm-shared-storage:/downloads:rw \
  qbtcontainers.azurecr.io/qbtstagingcontaineraha:latest
```

**2. Shared drive inside `/config`:**

```bash
docker run -d \
  --name=qb \
  --restart=unless-stopped \
  --shm-size 2g \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -e QB_DOWNLOAD_DIR=/config/Downloads \
  -p 4443:4443 \
  -v /mnt/vm-shared-storage:/config/Downloads:rw \
  qbtcontainers.azurecr.io/qbtstagingcontaineraha:latest
```

**3. Any other path, with a different host port and time zone:**

```bash
docker run -d \
  --name=qb \
  --restart=unless-stopped \
  --shm-size 2g \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -e TZ=Europe/London \
  -e QB_DOWNLOAD_DIR=/data/qb-files \
  -p 8443:4443 \
  -v /mnt/vm-shared-storage:/data/qb-files:rw \
  qbtcontainers.azurecr.io/qbtstagingcontaineraha:latest
```

Open it at `http://<host-ip>:8443` in example 3. Paths under `/config` (example 2)
can slow start-up on a network share; see
[why](#why-the-default-is-outside-config).

---

## Options

### `docker run` options

| Option | Purpose |
|---|---|
| `--name=qb` | Container name used by the commands below. |
| `--restart=unless-stopped` | Restart after a crash or host reboot. |
| `--shm-size 2g` | Shared memory for Chromium. Without enough, tabs crash on heavy pages. |
| `-p 4443:4443` | Publishes the web UI. Change the left side (`-p 8443:4443`) to use another host port. |
| `-v <share>:/downloads:rw` | Mounts the shared drive. The container-side path must equal `QB_DOWNLOAD_DIR`. |

### Environment variables

Set by this image:

| Variable | Default | Meaning |
|---|---|---|
| `QB_DOWNLOAD_DIR` | `/downloads` | Container path where downloads are saved and the file dialogs start. Absolute path only. Must match the container side of the `-v` mount. See [below](#changing-the-download-directory-qb_download_dir). |
| `APP_NAME` | `Query Builder` | Window/page title. Baked into the image. |
| `WEB_LISTENING_PORT` | `4443` | Port the web UI listens on inside the container. Baked in; if you change it, change `-p` too. |

From the base image ([`jlesage/chromium`](https://github.com/jlesage/docker-chromium)) — the ones you are likely to need:

| Variable | Default | Meaning |
|---|---|---|
| `USER_ID` | `1000` | User ID the app runs as. Set it to the owner of the shared drive (`id <username>` on the host). |
| `GROUP_ID` | `1000` | Group ID the app runs as. Same advice. |
| `TZ` | `Etc/UTC` | Time zone, e.g. `-e TZ=Europe/London`. |
| `DISPLAY_WIDTH` / `DISPLAY_HEIGHT` | `1920` / `1080` | Size of the virtual screen. |
| `SECURE_CONNECTION` | `0` | `1` serves the web UI over HTTPS (self-signed unless you supply a certificate). |
| `WEB_AUTHENTICATION` | `0` | `1` asks for a login before the web UI. Needs the base image's credentials setup. |

The base image documents many more; see its README for the full list.

---

## Changing the download directory (`QB_DOWNLOAD_DIR`)

`QB_DOWNLOAD_DIR` decides where the shared drive appears inside the container.
It drives all of these, so they always agree: Chromium's download folder, the
folder the download/save and upload dialogs open at, the "Downloads" shortcut
in the file chooser, and the permission-fixing service.

```bash
# default
-v /mnt/vm-shared-storage:/downloads:rw

# custom location
-e QB_DOWNLOAD_DIR=/config/Downloads \
-v /mnt/vm-shared-storage:/config/Downloads:rw
```

Rules:

- It must be an **absolute path**. Anything else (or a value containing a
  quote, backslash, `|` or `$`) is rejected and the container falls back to
  `/downloads`, with a message in `docker logs`.
- The `-v` mount must use the **same** path, or files land in the container's
  own storage instead of the shared drive.
- The directory is created if it does not exist.

### Why the default is outside `/config`

The base image recursively re-owns all of `/config` (to `USER_ID`/`GROUP_ID`) on
**every** start. If the shared drive is a network share (Azure Files / CIFS) and
is mounted inside `/config`, that becomes one network round trip per file and
can add minutes to startup — more as the share fills up. Mounting it outside
`/config` (the default `/downloads`) avoids this. If you do mount inside
`/config`, the container logs a note at start-up.

Do **not** set `TAKE_CONFIG_OWNERSHIP=0` to work around this: it disables the
ownership fix for the local `/config` data Chromium needs and causes a
permission-denied crash loop.

---

## Uploads and downloads

- **Downloads** (including *Download Results*, which uses the browser's save
  dialog) end up in `QB_DOWNLOAD_DIR`.
- **Uploads**: the file picker opens at `QB_DOWNLOAD_DIR` the first time.
- This starting-folder setup is applied only to a **fresh** `/config`. A
  container recreated against an existing `/config` volume keeps whatever the
  profile already remembered — use the replace procedure below, which removes
  that volume.
- Chromium creates downloaded files as `0600`. A small background service
  (`fix-downloads`) sets files to `666` and folders to `777` every 2 seconds so
  other host users and groups can read and write them. To be stricter, edit
  `FILE_MODE` / `DIR_MODE` in `root/etc/services.d/fix-downloads/run` and rebuild.

---

## Updating or replacing the container

Pull the latest image:

```bash
docker pull qbtcontainers.azurecr.io/qbtstagingcontaineraha:latest
```

then remove the running container **together with its own `/config` volume**,
and run the [Quick start](#quick-start) command again:

```bash
docker rm -f -v qb
```

`-v` removes only the container's own volume, never the shared drive.

---

## Checking it works

| Check | How |
|---|---|
| Container is running | `docker ps`, then open `http://<host-ip>:4443` |
| Download directory resolved | `docker logs qb \| grep set-download-dir` → `downloads directory is <path>` |
| Permission service running | `docker logs qb \| grep fix-downloads` |
| Lockdown policy loaded | In the session open `chrome://policy` — `URLBlocklist` and `URLAllowlist` should show Status **OK** |
| A blocked site is blocked | Try any site not in the allow list; you get *blocked by administrator* |

---

## Changing the site or allowed domains

[`policy.json`](policy.json) is the one place to edit:

1. Add the host to `URLAllowlist` (entries match the host **and its subdomains**;
   `mailto:*` allows mail links).
2. If it is the new landing page, update `HomepageLocation` and
   `RestoreOnStartupURLs`.
3. Update the bookmark in `root/defaults/Bookmarks` (`name` and `url`), and bump
   the version in its name on every release so the bookmark bar shows what is running.
4. Rebuild and republish the image.

---

## Build and publish

### 1. Our registry (`qbtcontainers.azurecr.io`)

```bash
docker login -u read-write -p <password> qbtcontainers.azurecr.io

docker build -t qbtcontainers.azurecr.io/qbtstagingcontaineraha:latest .
docker push qbtcontainers.azurecr.io/qbtstagingcontaineraha:latest
```

### 2. AHA's registry (Aridhia)

The image is mirrored to AHA's own registry, which the AHA environment pulls from:

```bash
docker login -u read-write -p <SOURCE_REGISTRY_PASSWORD> qbtcontainers.azurecr.io
docker pull qbtcontainers.azurecr.io/qbtstagingcontaineraha:latest
docker tag qbtcontainers.azurecr.io/qbtstagingcontaineraha:latest acrwesteuropeaddi.azurecr.io/0a6ed49f-321c-4320-b746-6b72de4f2640/fdsa_qbt_staging:latest
docker login -u fdsa-qbt -p <TARGET_REGISTRY_PASSWORD> acrwesteuropeaddi.azurecr.io
docker push acrwesteuropeaddi.azurecr.io/0a6ed49f-321c-4320-b746-6b72de4f2640/fdsa_qbt_staging:latest
```

| Registry | Image |
|---|---|
| Ours | `qbtcontainers.azurecr.io/qbtstagingcontaineraha:latest` |
| AHA (Aridhia) | `acrwesteuropeaddi.azurecr.io/0a6ed49f-321c-4320-b746-6b72de4f2640/fdsa_qbt_staging:latest` |

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Files appear in the container but not on the shared drive | `QB_DOWNLOAD_DIR` and the container side of `-v` differ. Make them identical. |
| "Permission denied" writing to the drive | `USER_ID` / `GROUP_ID` do not match the drive's owner. Use the values from `id <username>` on the host. |
| Slow start, long pause at start-up | The share is mounted inside `/config`. Mount it outside (default `/downloads`). |
| Dialogs still open at `/config` after changing settings | The old `/config` volume was reused. Run `docker rm -f -v qb` and start again. |
| `chrome://policy` shows an error on `URLAllowlist` | Expand the row to read the specific entry. Entries must be valid URL patterns (e.g. `host`, `https://host`, `mailto:*`). |
| Page crashes / blank tabs | Increase `--shm-size`. |
| A needed site is blocked | Add its host to `URLAllowlist` in `policy.json` and rebuild. |

---

## How it works (for maintainers)

- `Dockerfile` — based on `jlesage/chromium`; copies `policy.json` to both
  `/etc/chromium/policies/managed/` and `/etc/chromium-browser/policies/managed/`,
  and **deletes the base image's own `managed_policies.json` / `.bk`** there,
  which otherwise merge with ours and conflict (download directory, bookmarks).
- `root/etc/cont-init.d/59-set-download-dir.sh` — resolves `QB_DOWNLOAD_DIR`,
  writes it to `/var/run/qb-download-dir` and into the policy's
  `DownloadDirectory` / `DefaultDownloadDirectory`.
- `60-seed-bookmarks.sh` — copies `root/defaults/Bookmarks` into the profile.
- `61-seed-downloads-dir.sh` — points the GTK file dialog's "Downloads" shortcut at the directory.
- `62-seed-picker-dir.sh` — seeds the save and upload dialogs' starting folder on a fresh profile.
- `root/etc/services.d/fix-downloads/` — the permission-relaxing service.
- `root/etc/services.d/app/params` — Chromium flags (`--test-type` hides the
  `--no-sandbox` infobar, `--start-maximized`, profile at `/config/chromium`).
