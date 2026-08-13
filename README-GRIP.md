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
set to `/downloads`.

No mount paths changed. **Do not** change `-v /mnt/vm-shared-storage:/downloads:rw`
to anything else — that mount was already correct.

> **Important for existing deployments:** Chromium remembers the last folder
> used in a save dialog, and that memory lives in its profile under `/config`.
> If the container is recreated against an existing `/config` volume, the
> dialog can still open at the old location even with the policy fixed. See
> step 2 below — remove the old volume so the profile starts clean.

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

### 2. Remove the currently running container and its `/config` volume

A restart won't pick up the new image — it has to be recreated. Remove the
anonymous `/config` volume along with it, so Chromium's profile (which
remembers the last folder used in a save dialog) starts clean:

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

### 5. Confirm the policy conflict is gone

In the browser session, open `chrome://policy` and check:

- `DefaultDownloadDirectory` reads `/downloads` (not `/config/Downloads`) and
  no longer shows **"Superseding"**.
- `ManagedBookmarks` no longer shows **"Warning, Conflict"**.

If either still shows the old value, the base image's policy files were not
removed — re-check the `rm -f` step in the Dockerfile actually ran during the
build.

### 6. Verify the actual fix

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
