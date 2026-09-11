# Query Builder Container — GRIP Production Image

Build and delivery runbook for the **production** GRIP image. This branch
(`claude/grip-prod-image`) is the staging GRIP branch with the target URL
switched to production — it carries every downloads-location fix described in
[README-GRIP.md](README-GRIP.md).

| | |
|---|---|
| Target site | `https://fdsa-query-builder.alzheimersdata.org/qbt/` |
| Image tag | `qbtcontainers.azurecr.io/qbtcontainer:grip` |
| Bookmark label | `Query Builder v4` (no "(staging)" suffix) |
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
| `root/defaults/Bookmarks` → `name` | `Query Builder v4 (staging)` | `Query Builder v4` |

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

Set `QB_DOWNLOAD_DIR` to wherever you mount the share — the container points
Chromium, the file dialog and the permission-fixing service at that path.
GRIP mounts inside `/config`:

```bash
docker run -d \
  --name=qb \
  --restart=unless-stopped \
  --shm-size 2g \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -e QB_DOWNLOAD_DIR=/config/Downloads \
  -p 4443:4443 \
  -v /mnt/vm-shared-storage:/config/Downloads:rw \
  qbtcontainers.azurecr.io/qbtcontainer:grip
```

**Three things to check before running this:**

1. `/mnt/vm-shared-storage` is the staging GRIP VM's share path — confirm the
   production VM's.
2. The mount target and `QB_DOWNLOAD_DIR` must be **the same path**, and it is
   **case-sensitive**: `/config/Downloads` ≠ `/config/downloads`.
3. Mounting inside `/config` means the base image's per-start recursive
   `chown` walks the share. Fine on local disk; on a large network share it
   slows startup — mount outside `/config` and drop the env var instead. The
   container logs a warning when the path is inside `/config`. See
   [README-GRIP.md](README-GRIP.md#trade-off-inside-config-vs-outside).

Likewise confirm `USER_ID`/`GROUP_ID` match the owner of the production
share, so downloaded files land with usable ownership.

---

## Verification

The steps below use `<DOWNLOAD_DIR>` as a placeholder for whatever you set
`QB_DOWNLOAD_DIR` to in Step 6 (`/config/Downloads` in the example above).

**1. The mount:**

```bash
docker inspect qb --format '{{range .Mounts}}{{if eq .Destination "<DOWNLOAD_DIR>"}}{{.Type}}: {{.Source}} -> {{.Destination}}{{end}}{{end}}'
```

Expect `bind: <your shared path> -> <DOWNLOAD_DIR>`. If it says `volume`, the
bind mount didn't take.

**2. The picker seed applied:**

```bash
docker logs qb 2>&1 | grep -E "seed-picker-dir|set-download-dir"
```

Expect `[set-download-dir] downloads directory is <DOWNLOAD_DIR>` and
`[seed-picker-dir] seeded /config/chromium/Default/Preferences with
<DOWNLOAD_DIR> as the last-picked directory`. If the latter instead says
*"already exists; leaving the profile alone"*, the old volume was reused —
redo step 5 with `-v`.

**3. Policy is clean.** Open `chrome://policy` in the session:

- `HomepageLocation` → `https://fdsa-query-builder.alzheimersdata.org/qbt/`
- `DownloadDirectory` and `DefaultDownloadDirectory` → `<DOWNLOAD_DIR>`
- Neither shows **"Superseding"**
- `ManagedBookmarks` no longer shows **"Warning, Conflict"**

**4. The bookmark.** The bookmark bar should show **`Query Builder v4`** (no
"(staging)" suffix) — confirms the right build at a glance.

**5. The actual user journey.** Run a query, click **Download Results**, and
confirm the save dialog opens directly at the shared drive — no navigating
past `/config` first. Then confirm the file is on the share:

```bash
find /mnt/vm-shared-storage -iname "<test filename>"
```

It should be there and **not** under `/var/lib/docker/volumes/.../_data`.

**6. Startup time.** Time how long the container took to become ready and
compare against a known-good baseline. A sudden multi-minute startup means
the mount is behaving like a network share under `/config`'s recursive
chown, not local disk — see
[README-GRIP.md](README-GRIP.md#trade-off-inside-config-vs-outside) and
re-check the mount type before this carries production traffic.

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
