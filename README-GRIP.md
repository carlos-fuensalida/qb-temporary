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

The volume mount was never the problem — `docker inspect qb` confirmed
`bind: /mnt/vm-shared-storage -> /downloads` throughout, and automatic
downloads were landing on the shared drive correctly.

The problem was a **conflict between two Chromium policy files**. The base
image ships its own `managed_policies.json` (plus a `managed_policies.json.bk`
sample) into `/etc/chromium/policies/managed/` — the same directory this
project's `policy.json` is copied into. Chromium merges *every* file in that
directory, and the base image's file sets:

```json
"DefaultDownloadDirectory": "/config/Downloads"
```

`chrome://policy` on the deployed container showed that value with status
**"OK, Superseding"**, overriding this project's `DownloadDirectory:
"/downloads"` for the purpose of the file dialog's starting folder. So the
native save dialog opened inside the container's local `/config` instead of
the shared mount, and anything saved from it landed in the container's
internal Docker volume — which is exactly where `qbdownload.zip` was found
(`/var/snap/docker/.../volumes/<hash>/_data/qbdownload.zip`).

The same collision made `ManagedBookmarks` report **"Warning, Conflict"**,
against the sample bookmarks defined in the `.bk` file. The `.bk` extension
is not a guard — Chromium loads it as policy too.

## The fix

The Dockerfile now deletes the base image's `managed_policies.json` and
`managed_policies.json.bk`, so `policy.json` is the single source of policy
truth and there is no merge conflict to reason about. The one key worth
keeping from that file, `ExtensionInstallForcelist`, is folded into
`policy.json`. `DownloadDirectory` and `DefaultDownloadDirectory` are both
set to the configured downloads directory.

The mount path itself is now a deployment choice rather than something this
image fixes — set `QB_DOWNLOAD_DIR` to wherever you mount the share. See
[Choosing where downloads go](#choosing-where-downloads-go).

## The save dialog's starting folder — a second, separate mechanism

Fixing the policy conflict above was necessary but not sufficient, because
Query Builder does not save through a normal browser download at all. Its
"Download Results" button uses the **File System Access API**
(`window.showSaveFilePicker`) — recognisable by the dialog's title bar
reading *"Warning: this site can see edits you make"*.

That API ignores `DownloadDirectory` and `DefaultDownloadDirectory`
completely. Its starting folder comes from one of two places:

1. a `startIn` hint the web page passes — Query Builder passes none, and
   adding one is a change only the Query Builder application team can make;
2. failing that, the folder that origin last picked.

With nothing remembered, Chromium falls back to `$HOME` — `/config` — which
is what users saw on a freshly started container.

`root/etc/cont-init.d/62-seed-picker-dir.sh` seeds that "last picked"
memory with the configured downloads directory before Chromium first
launches, for every Query Builder origin this image is used against. A brand new container then behaves
as though a user had already saved there once.

> **This only applies to a fresh profile.** The script deliberately does not
> touch an existing `Preferences` file — editing nested JSON in a live
> profile without a JSON parser (the image has no `jq` or `python`) risks
> corrupting it, and an existing profile already has a memory of its own.
> That makes the `-v` in step 2 below **required**, not optional: without it
> the container keeps the old profile and the seed never applies.

---

## Building the image

Build on a VM with internet access and Docker. No registry login is needed —
the tag is only a name, and it's only required if you later choose to push.

```bash
git clone -b claude/downloads-folder-location-imjnz1 \
  https://github.com/carlos-fuensalida/qb-temporary.git
cd qb-temporary

docker build -t qbtcontainers.azurecr.io/qbtstagingcontainer:grip .
```

### Post-build checks — run both

These take seconds and catch the two mistakes that would otherwise only show
up after a ~1 GB transfer to the target VM.

**1. The base image's conflicting policy files are gone:**

```bash
docker run --rm --entrypoint sh qbtcontainers.azurecr.io/qbtstagingcontainer:grip \
  -c 'ls /etc/chromium/policies/managed/'
```

Expect **only** `policy.json`. If `managed_policies.json` or
`managed_policies.json.bk` appear, the `rm -f` layer didn't run and the
download-location bug is still present.

**2. The staging URL was baked in, not production:**

```bash
docker run --rm --entrypoint sh qbtcontainers.azurecr.io/qbtstagingcontainer:grip \
  -c 'grep -E "HomepageLocation|RestoreOnStartupURLs" /etc/chromium/policies/managed/policy.json'
```

Expect `qbt-staging.fdsaservices.com`. Seeing
`fdsa-query-builder.alzheimersdata.org` means the production branch
(`claude/grip-prod-image`) was cloned by mistake.

### Save to a `.tar`

```bash
docker save -o qbt-grip.tar qbtcontainers.azurecr.io/qbtstagingcontainer:grip
```

Or compressed, to cut transfer size:

```bash
docker save qbtcontainers.azurecr.io/qbtstagingcontainer:grip | gzip > qbt-grip.tar.gz
```

Then transfer it to the target VM by whatever channel you already use.

---

## Choosing where downloads go

`QB_DOWNLOAD_DIR` (default `/downloads`) is the single place this is
configured. At container start, `59-set-download-dir.sh` resolves it and
propagates it to everything that needs it:

| Consumer | What it controls |
|---|---|
| `policy.json` → `DownloadDirectory` / `DefaultDownloadDirectory` | where automatic downloads land |
| `user-dirs.dirs` → `XDG_DOWNLOAD_DIR` | the dialog sidebar's "Downloads" shortcut |
| `gtk-3.0/bookmarks` | the same shortcut, for dialogs that read bookmarks instead |
| `62-seed-picker-dir.sh` | the folder the save dialog **opens at** |
| `fix-downloads` service | which directory gets its permissions relaxed |

Set it to whatever you mount the share at. Nothing else needs editing, and
the value is validated — a relative path or one containing quotes is rejected
with a log line and falls back to `/downloads` rather than corrupting the
policy file.

### Trade-off: inside `/config` vs outside

Mounting the share **inside** `/config` (as GRIP does) is simpler — the
dialog's own home directory contains the share, so users need no navigation
at all. But the base image recursively `chown`s the whole of `/config` on
**every** container start. If the share is a network filesystem (Azure
Files/CIFS), that becomes a per-file network round trip and can add minutes
to startup, getting worse as the share fills — the exact problem
[README-STAG.md](README-STAG.md) documents moving *away* from for the AKS
workspaces.

So:

- **Local disk or a fast mount** → inside `/config` is fine.
- **Network share that grows large** → mount outside `/config` (leave
  `QB_DOWNLOAD_DIR` at its `/downloads` default).

The container logs a warning at startup when the configured path is inside
`/config`, so this is visible in `docker logs qb` rather than a silent
surprise.

---

## Deploying: load the image from the `.tar` file

Steps below run on the target VM, and assume `qbt-grip.tar` has arrived.

### 1. Load the image

```bash
docker load -i qbt-grip.tar
# or, if gzipped:
gunzip -c qbt-grip.tar.gz | docker load
```

Confirm it's there:

```bash
docker images | grep grip
```

You should see `qbtcontainers.azurecr.io/qbtstagingcontainer   grip   ...`.

### 2. Remove the currently running container and its `/config` volume

A restart won't pick up the new image — it has to be recreated. Removing the
anonymous `/config` volume is **required**, not optional: the picker-directory
seed only applies to a fresh Chromium profile, so a container recreated
against the old volume will still open the dialog at the old location.

```bash
docker rm -f -v qb
```

`-v` removes the container's anonymous volumes. It does **not** touch the
shared drive — that's a bind mount to a host path, not a Docker volume, so
`/mnt/vm-shared-storage` and everything in it is untouched.

Confirm the old `/config` volume is gone (optional):

```bash
docker volume ls -qf dangling=true
```

### 3. Run the new container

Where the shared drive is mounted is your choice — set `QB_DOWNLOAD_DIR` to
match wherever you mount it, and the container points Chromium, the file
dialog and the permission-fixing service at that path. See
[Choosing where downloads go](#choosing-where-downloads-go).

**GRIP — share mounted inside `/config`:**

```bash
docker run -d \
  --name=qb \
  --restart=unless-stopped \
  --shm-size 2g \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -e QB_DOWNLOAD_DIR=/config/Downloads \
  -p 4443:4443 \
  -v /mnt/vm-shared-storage:/config/Downloads:rw \
  qbtcontainers.azurecr.io/qbtstagingcontainer:grip
```

**AKS automation workspaces — share mounted outside `/config`** (the
default, so no env var needed):

```bash
docker run -d \
  --name=qb \
  --restart=unless-stopped \
  --shm-size 2g \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -p 4443:4443 \
  -v /files/shared/drive:/downloads:rw \
  qbtcontainers.azurecr.io/qbtstagingcontainer:grip
```

The mount target and `QB_DOWNLOAD_DIR` must be **the same path**, and the
path is **case-sensitive** — `/config/Downloads` and `/config/downloads` are
different directories on Linux.

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

### 5. Confirm the policy conflict is gone

In the browser session, open `chrome://policy` and check:

- `DefaultDownloadDirectory` reads `/downloads` (not `/config/Downloads`) and
  no longer shows **"Superseding"**.
- `ManagedBookmarks` no longer shows **"Warning, Conflict"**.

If either still shows the old value, the base image's policy files were not
removed — re-check the `rm -f` step in the Dockerfile actually ran during the
build.

### 6. Confirm the picker seed landed

```bash
docker logs qb 2>&1 | grep seed-picker-dir
```

Expect `seeded /config/chromium/Default/Preferences with /downloads as the
last-picked directory`. If it instead says *"already exists; leaving the
profile alone"*, the old `/config` volume was reused — redo step 2 with `-v`.

### 7. Verify the actual fix

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
