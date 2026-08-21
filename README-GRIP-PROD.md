# Query Builder Container — GRIP Production Image

Build and delivery runbook for the **production** GRIP image. This branch
(`claude/grip-prod-image`) is the staging GRIP branch with the target URL
switched to production — it carries every downloads-location fix described in
[README-GRIP.md](README-GRIP.md).

| | |
|---|---|
| Target site | `https://fdsa-query-builder.alzheimersdata.org/qbt/` |
| Image tag | `qbtcontainers.azurecr.io/qbtcontainer:grip` |
| Bookmark label | `Query Builder v3` (no "(staging)" suffix) |
| Delivery | `docker save` → `.tar` → air-gapped VM |

---

## What differs from the staging GRIP image

Only the target URL and its label. Everything else — the policy
consolidation, the `/downloads` mount, the picker-directory seed — is
identical.

| File | Staging | Production |
|---|---|---|
| `policy.json` → `HomepageLocation` | `qbt-staging.fdsaservices.com` | `fdsa-query-builder.alzheimersdata.org` |
| `policy.json` → `RestoreOnStartupURLs` | `qbt-staging.fdsaservices.com` | `fdsa-query-builder.alzheimersdata.org` |
| `root/defaults/Bookmarks` → `url` | `qbt-staging.fdsaservices.com` | `fdsa-query-builder.alzheimersdata.org` |
| `root/defaults/Bookmarks` → `name` | `Query Builder v3 (staging)` | `Query Builder v3` |

The production host was already present in `URLAllowlist`, and
`62-seed-picker-dir.sh` already seeds the production origin
(`https://fdsa-query-builder.alzheimersdata.org:443,*`), so neither needed a
change.

---

## Step 1 — Build (on a VM with internet + Docker)

```bash
git clone https://github.com/carlos-fuensalida/qb-temporary.git
cd qb-temporary
git checkout claude/grip-prod-image

docker build -t qbtcontainers.azurecr.io/qbtcontainer:grip .
```

No registry login is needed to build — the tag is just a name. You only need
`docker login` if you later choose to push it.

Confirm the build baked in the production URL, not staging:

```bash
docker run --rm --entrypoint sh qbtcontainers.azurecr.io/qbtcontainer:grip \
  -c 'grep HomepageLocation /etc/chromium/policies/managed/policy.json'
```

Expect `fdsa-query-builder.alzheimersdata.org`. Also confirm the base image's
conflicting policy file is gone:

```bash
docker run --rm --entrypoint sh qbtcontainers.azurecr.io/qbtcontainer:grip \
  -c 'ls /etc/chromium/policies/managed/'
```

Expect **only** `policy.json` — no `managed_policies.json`, no
`managed_policies.json.bk`. If either is present, the `rm -f` layer in the
Dockerfile didn't run and the download-location bug will come back.

## Step 2 — Save to a tar

```bash
docker save -o qbt-grip-prod.tar qbtcontainers.azurecr.io/qbtcontainer:grip
```

Expect a large file (roughly 1 GB — the Chromium base image is not small).
To shrink it for transfer:

```bash
docker save qbtcontainers.azurecr.io/qbtcontainer:grip | gzip > qbt-grip-prod.tar.gz
```

## Step 3 — Transfer to the air-gapped VM

Whatever channel you already use — `scp`, approved removable media, a file
drop. Nothing image-specific here.

## Step 4 — Load on the air-gapped VM

```bash
docker load -i qbt-grip-prod.tar
# or, if gzipped:
gunzip -c qbt-grip-prod.tar.gz | docker load
```

Confirm it registered under the expected name:

```bash
docker images | grep qbtcontainer
```

## Step 5 — Replace the running container

The `-v` is **required**, not optional. The picker-directory seed only
applies to a fresh Chromium profile, so reusing the old `/config` volume
means the save dialog keeps opening at the old location.

```bash
docker rm -f -v qb
```

`-v` removes the container's anonymous volumes only. The shared drive is a
bind mount to a host path, not a Docker volume, so its contents are
untouched.

## Step 6 — Run

```bash
docker run -d \
  --name=qb \
  --restart=unless-stopped \
  --shm-size 2g \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -p 4443:4443 \
  -v /mnt/vm-shared-storage:/downloads:rw \
  qbtcontainers.azurecr.io/qbtcontainer:grip
```

**Check the shared-storage path before running this.** `/mnt/vm-shared-storage`
is the path on the staging GRIP VM; the production VM may mount its share
elsewhere. Only the left side changes — keep `:/downloads:rw` exactly as is.

Likewise confirm `USER_ID`/`GROUP_ID` match the owner of the production
share, so downloaded files land with usable ownership.

---

## Verification

**1. The mount:**

```bash
docker inspect qb --format '{{range .Mounts}}{{if eq .Destination "/downloads"}}{{.Type}}: {{.Source}} -> {{.Destination}}{{end}}{{end}}'
```

Expect `bind: <your shared path> -> /downloads`. If it says `volume`, the
bind mount didn't take.

**2. The picker seed applied:**

```bash
docker logs qb 2>&1 | grep seed-picker-dir
```

Expect `seeded /config/chromium/Default/Preferences with /downloads as the
last-picked directory`. If it says *"already exists; leaving the profile
alone"*, the old volume was reused — redo step 5 with `-v`.

**3. Policy is clean.** Open `chrome://policy` in the session:

- `HomepageLocation` → `https://fdsa-query-builder.alzheimersdata.org/qbt/`
- `DownloadDirectory` and `DefaultDownloadDirectory` → `/downloads`
- Neither shows **"Superseding"**
- `ManagedBookmarks` no longer shows **"Warning, Conflict"**

**4. The actual user journey.** Run a query, click **Download Results**, and
confirm the save dialog opens directly at `downloads` — no navigating. Then
confirm the file is on the share:

```bash
find /mnt/vm-shared-storage -iname "<test filename>"
```

It should be there and **not** under `/var/lib/docker/volumes/.../_data`.

---

## Known outstanding issue — read before going live

`chrome://policy` on the staging container reported **`URLAllowlist` — Status:
Error**, meaning part of the kiosk allowlist is being rejected by Chromium.
This is unrelated to the downloads work and was never diagnosed, because
changing lockdown rules on a guess is what caused the original problem.

It matters more in production than in staging: a partially-rejected allowlist
means the URL lockdown may not be enforcing everything it appears to. Likely
culprits in `policy.json` are the bare `mailto` / `mailto:` entries (not valid
URL patterns) and the duplicated
`https://discover.alzheimersdata.org` entry.

To diagnose: open `chrome://policy`, expand the `URLAllowlist` row, and read
the specific error. Worth resolving before this image carries production
traffic.

---

## Note on the bookmark checksum

`root/defaults/Bookmarks` contains a `checksum` field that is **not** updated
when the URL or name changes. Chromium tolerates the mismatch — the bookmark
renders correctly in the deployed staging image, and commit `fb47785` changed
the label the same way without touching it. No action needed; just don't be
alarmed by the stale value.
