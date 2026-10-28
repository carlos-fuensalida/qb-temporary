# Query Builder Container — Production Fix Summary

This document is for the IT team supporting the production environment. It
covers the container startup-time issue you flagged and the fix now in this
branch, plus the updated `docker run` command to deploy it.

---

## The issue you reported

Query Builder containers running in the automation workspaces (AKS) were
taking multiple minutes to start, and start-up time kept growing as the
shared downloads drive accumulated more files.

## Root cause

The container's base image runs a startup step that recursively takes
ownership (`chown`) of its entire internal `/config` directory on **every**
launch, so the app can run as the workspace's configured user/group. Your
downloads volume — the shared network drive (Azure Files/CIFS) — was mounted
inside that same `/config` directory (`/config/Downloads`). Because that
drive is a network filesystem, the recursive ownership walk turned into a
network round trip per file/folder, which is what drove the multi-minute
startup and the slowdown as the drive filled up.

We also confirmed that disabling that ownership step outright is **not** a
safe fix — several local, non-shared paths inside `/config` genuinely need it
and will crash-loop with permission errors if it's skipped.

## The fix

We moved the downloads location **out of `/config` entirely**, to `/downloads`.
The container's ownership step now only ever touches local disk, regardless
of how large the shared downloads drive grows or how it's mounted. Downloaded
files are still automatically made readable/writable, exactly as before —
only the mount path changed.

## Action needed on your side

Update wherever your shared/network drive is mounted into the container —
pod spec, Helm values, `docker run` command, etc. — so the **target path
changes from `/config/Downloads` to `/downloads`**. Nothing else about the
mount (the network drive itself, its permissions, its CSI/uid-gid settings)
needs to change.

## Updated `docker run` command (production)

```bash
docker run -d \
  --name=qb \
  --restart=unless-stopped \
  --shm-size 2g \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -p 4443:4443 \
  -v /files/shared/drive:/downloads:rw \
  qbtcontainers.azurecr.io/qbtcontainer:latest
```

Replace `/files/shared/drive` with your actual shared/network path (in AKS,
this is the same Azure Files mount you already have — just retarget it to
`/downloads`).

Target site: `https://fdsa-query-builder.alzheimersdata.org/qbt/`

## How to verify

- Container start time should return to a few seconds, independent of how
  much is already in the shared downloads drive.
- Files downloaded through Query Builder should still land on the shared
  drive and be readable/writable as before.
