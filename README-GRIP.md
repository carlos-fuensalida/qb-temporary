# Query Builder Container — GRIP Downloads-Location Fix

This document is for the developer deploying the fixed image to the GRIP
environment. It covers the issue that was reported, what changed, and the
exact steps to load and run the new image from a `.tar` file.

---

## The issue reported

The GRIP container's downloads were showing up in the wrong location. A
downloaded file (`qbdownload.zip`) was found sitting inside the container's
internal `/config` storage instead of the shared network drive.

## Root cause

Two separate mechanisms control where a file ends up, and only one of them
was configured:

- **Automatic/silent downloads** are controlled by Chromium's
  `DownloadDirectory` policy (`policy.json`), which already correctly points
  at `/downloads` — the shared drive, bind-mounted via `-v ...:/downloads:rw`.
  This part was working.
- **Manual saves** (`Ctrl+S`, "Save Page As", the native file-picker's
  "Downloads" shortcut) are controlled separately, by XDG user-dirs
  (`~/.config/user-dirs.dirs`) — an OS-level setting the image never set.
  Left unset, it fell back to the container's default home location
  (`/config`), which sits on its own internal Docker volume — not the shared
  drive, not visible outside the container.

That's why `qbdownload.zip` was found inside a Docker-managed volume
(`/var/snap/docker/.../volumes/<hash>/_data/qbdownload.zip`) mounted at
`/config`, while the actual shared-drive mount (`/downloads`) was confirmed
correct the whole time via `docker inspect qb`.

## The fix

`root/etc/cont-init.d/61-seed-downloads-dir.sh` runs on every container start
and:
- Writes `XDG_DOWNLOAD_DIR="/downloads"` into `user-dirs.dirs`.
- Disables `xdg-user-dirs-update` so it can't silently reset that back.
- Seeds a matching `/downloads` bookmark into the GTK file-picker sidebar
  directly, as a second safety net.

No mount paths changed. **Do not** change `-v /mnt/vm-shared-storage:/downloads:rw`
to anything else — that mount was already correct.

---

## Deploying the fix: load the image from a `.tar` file

This image is tagged `qbtcontainers.azurecr.io/qbtstagingcontainer:grip` and
delivered as a `.tar` file (e.g. because this VM can't reach the registry
directly). Steps below assume you've already received `qbt-grip.tar`.

### 1. Load the image

```bash
docker load -i qbt-grip.tar
```

Confirm it's there:

```bash
docker images | grep grip
```

You should see `qbtcontainers.azurecr.io/qbtstagingcontainer   grip   ...`.

### 2. Remove the currently running container

A restart won't pick up the new image — it has to be recreated:

```bash
docker rm -f qb
```

### 3. Run the new container

```bash
docker run -d \
  --name=qb \
  --restart=unless-stopped \
  --shm-size 2g \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -p 4443:4443 \
  -v /mnt/vm-shared-storage:/downloads:rw \
  qbtcontainers.azurecr.io/qbtstagingcontainer:grip
```

Adjust `/mnt/vm-shared-storage` only if this VM's shared-storage path
differs — keep the `:/downloads:rw` side exactly as-is.

### 4. Confirm the mount

```bash
docker inspect qb --format '{{range .Mounts}}{{if eq .Destination "/downloads"}}{{.Type}}: {{.Source}} -> {{.Destination}}{{end}}{{end}}'
```

Expect:

```
bind: /mnt/vm-shared-storage -> /downloads
```

### 5. Verify the actual fix

Open `http://<host-ip>:4443`, manually save a test file (`Ctrl+S` or
"Save Page As" — not an automatic download, since that path already worked
before this fix), then confirm it landed in the right place:

```bash
find /mnt/vm-shared-storage -iname "<test filename>"
```

It should show up there, and **not** under
`/var/snap/docker/.../volumes/.../_data`.

---

## How to verify

- A manually-saved file lands on the shared drive (`/mnt/vm-shared-storage`),
  not inside the container's internal `/config` volume.
- The native file-picker's "Downloads" shortcut opens directly into the
  shared drive instead of an empty/unrelated folder.
- Automatic/silent downloads continue to work exactly as before — only the
  manual-save path changes.
