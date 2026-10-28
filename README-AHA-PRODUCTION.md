# Query Builder Container — AHA Production

A Chromium browser in a Docker container that opens **Query Builder**
(`https://fdsa-query-builder.alzheimersdata.org/qbt/`) and is locked to it. Users reach it from their own web browser
(noVNC, port 4443) — nothing is installed on their machine. Downloads use a
shared drive mounted into the container.

| | |
|---|---|
| Release | **v7** (the v3 code line — AHA rejected v6) |
| Image | `qbtcontainers.azurecr.io/qbtcontaineraha:latest` (also tagged `:v7`) |
| Target site | `https://fdsa-query-builder.alzheimersdata.org/qbt/` |
| Web port | `4443` |
| Bookmark shown in the browser | `Query Builder v7` |

- **Normal browser window** — toolbar, Home button, back/forward, reload — so a
  user who gets stuck can recover without restarting the container.
- **Locked down** to Query Builder and its allowed login (SSO) domains by a
  Chromium managed policy ([`policy.json`](policy.json)). Any other URL is blocked.
- **Downloads** go to the mounted shared drive at `/downloads` and are made
  readable and writable for other users and groups automatically.

> **AHA and GRIP are different projects.** This document covers the AHA image
> only. GRIP has its own code, image names and documents
> (`README-GRIP-STAGING.md`, `README-GRIP-PRODUCTION.md`) and carries the
> `QB_DOWNLOAD_DIR` / file-dialog work that AHA does **not** have. Do not mix
> their instructions: in particular, `QB_DOWNLOAD_DIR` does nothing in this image.

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
  qbtcontainers.azurecr.io/qbtcontaineraha:latest
```

Then open `http://<host-ip>:4443`. You land on Query Builder in a Chromium window.

The shared drive **must be mounted at `/downloads`** — that path is fixed in
this image (see [Why `/downloads`](#why-downloads-and-not-configdownloads)).
Replace `/mnt/vm-shared-storage` with the host path of the drive (or the
folder of it that downloads should land in).

### Same thing with Docker Compose

```yaml
services:
  qb:
    image: qbtcontainers.azurecr.io/qbtcontaineraha:latest
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

### Running on ECS / AKS

Mount the shared volume (EFS, Azure Files) at **`/downloads`** in the
container definition, not at `/config/Downloads`:

```json
"mountPoints": [
  { "sourceVolume": "efs-volume", "containerPath": "/downloads", "readOnly": false }
]
```

If the volume holds several folders (for example `workspace_files/...`), mount
the sub-folder that downloads should land in, or the whole volume, and users
will navigate from `/downloads`.

---

## Options

| Option | Purpose |
|---|---|
| `--shm-size 2g` | Shared memory for Chromium. Without enough, tabs crash on heavy pages. |
| `-p 4443:4443` | Web (noVNC) port. |
| `-v <share>:/downloads:rw` | Mounts the shared drive. The container path is always `/downloads`. |
| `--restart=unless-stopped` | Comes back after a host reboot. |

### Environment variables

| Variable | Default | What it does |
|---|---|---|
| `USER_ID` | `1000` | User ID the app runs as. Set it to the owner of the shared drive (`id <username>` on the host). |
| `GROUP_ID` | `1000` | Group ID the app runs as. Same advice. |
| `WEB_LISTENING_PORT` | `4443` | Port inside the container. Baked into the image. |
| `APP_NAME` | `Query Builder` | Window/page title. Baked into the image. |

Further variables come from the base image
([`jlesage/chromium`](https://github.com/jlesage/docker-chromium)); see its README.

---

## Why `/downloads` and not `/config/Downloads`

The base image recursively re-owns all of `/config` (to `USER_ID`/`GROUP_ID`) on
**every** start. If the shared drive is a network share (Azure Files / CIFS /
EFS) and is mounted inside `/config`, that becomes one network round trip per
file and adds minutes to startup — more as the share fills up. Mounting it at
`/downloads`, outside `/config`, avoids this. Chromium is pointed at it by the
`DownloadDirectory` policy in [`policy.json`](policy.json).

Do **not** set `TAKE_CONFIG_OWNERSHIP=0` to work around this: it disables the
ownership fix for the local `/config` data Chromium needs and causes a
permission-denied crash loop.

---

## Uploads and downloads

- **Downloads** are saved to `/downloads`.
- Chromium creates downloaded files as `0600`. A small background service
  (`fix-downloads`) sets files to `666` and folders to `777` every 2 seconds so
  other host users and groups can read and write them. To be stricter, edit
  `FILE_MODE` / `DIR_MODE` in `root/etc/services.d/fix-downloads/run` and rebuild.
- This release does **not** seed the starting folder of the browser's save and
  upload dialogs. Where a dialog opens is Chromium's own choice; users pick
  `/downloads` (the **Downloads** shortcut or the path bar) in the dialog.
  Changing the starting folder is a GRIP-only feature.

---

## Updating or replacing the container

Pull the image (`:latest` can be a stale local copy, so always pull):

```bash
docker pull qbtcontainers.azurecr.io/qbtcontaineraha:latest
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
| Right release | The bookmark bar reads `Query Builder v7` |
| Container is running | `docker ps`, then open `http://<host-ip>:4443` |
| Permission service running | `docker logs qb \| grep fix-downloads` |
| Lockdown policy loaded | In the session open `chrome://policy` — `URLBlocklist` and `URLAllowlist` should show Status **OK**, and `DownloadDirectory` should be `/downloads` |
| Downloads reach the drive | Download a file, then `ls -la <host-path>` on the host |
| A blocked site is blocked | Try any site not in the allow list; you get *blocked by administrator* |

---

## Changing the site or allowed domains

[`policy.json`](policy.json) is the one place to edit:

1. Add the host to `URLAllowlist` (entries match the host **and its subdomains**).
2. If it is the new landing page, update `HomepageLocation` and
   `RestoreOnStartupURLs`.
3. Update the bookmark in `root/defaults/Bookmarks` (`name` and `url`), and bump
   the version in its name on every release so the bookmark bar shows what is running.
4. Rebuild and republish the image.

---

## Build and publish

AHA pulls the image straight from our registry (`qbtcontainers.azurecr.io`),
so publishing is a single push. Push both tags so a pull of `:latest` gets v7:

```bash
docker login -u read-write -p <password> qbtcontainers.azurecr.io

docker build -t qbtcontainers.azurecr.io/qbtcontaineraha:v7 -t qbtcontainers.azurecr.io/qbtcontaineraha:latest .
docker push qbtcontainers.azurecr.io/qbtcontaineraha:v7
docker push qbtcontainers.azurecr.io/qbtcontaineraha:latest
```

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Files appear in the container but not on the shared drive | The drive is not mounted at `/downloads`. Check `docker inspect qb --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'`. |
| "Permission denied" writing to the drive | `USER_ID` / `GROUP_ID` do not match the drive's owner. Use the values from `id <username>` on the host. |
| Slow start, long pause at start-up | The share is mounted inside `/config`. Mount it at `/downloads`. |
| The save dialog opens somewhere else | Expected in this release (no dialog seeding). Choose `/downloads` in the dialog. |
| Bookmark does not say v7 | An old image is running. `docker pull`, then `docker rm -f -v qb` and run again. |
| `chrome://policy` shows an error on `URLAllowlist` | Expand the row to read the specific entry. Entries must be valid URL patterns (e.g. `host`, `https://host`, `mailto:*`). |
| Page crashes / blank tabs | Increase `--shm-size`. |
| A needed site is blocked | Add its host to `URLAllowlist` in `policy.json` and rebuild. |

---

## How it works (for maintainers)

- `Dockerfile` — based on `jlesage/chromium`; copies `policy.json` to both
  `/etc/chromium/policies/managed/` and `/etc/chromium-browser/policies/managed/`,
  creates `/downloads`, and sets `APP_NAME` and the web port.
- `policy.json` — URL allow list, homepage, `DownloadDirectory=/downloads`.
- `root/etc/cont-init.d/60-seed-bookmarks.sh` — copies `root/defaults/Bookmarks`
  into the profile.
- `root/etc/services.d/fix-downloads/` — the permission-relaxing service
  (watches `/downloads`).
- `root/etc/services.d/app/params` — Chromium flags (`--test-type` hides the
  `--no-sandbox` infobar, `--start-maximized`, profile at `/config/chromium`).
- Release history: v3 was the last version AHA accepted; v6 (the
  `QB_DOWNLOAD_DIR` build) was rejected; **v7 is v3 re-released**, with only the
  bookmark label changed.
