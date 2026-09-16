# QB Container — Query Builder browser

This repo builds a Docker container that runs a dedicated Chromium browser
(via [`jlesage/chromium`](https://github.com/jlesage/docker-chromium) and its
noVNC web layer) opening **Query Builder**. Users reach it entirely through
their own web browser — nothing to install client-side.

**`main` holds no code.** It's the map for the six branches that do — read
this before touching any of them.

---

## The branch matrix

There are two independent choices: **flavor** (what the container looks
like) and **environment** (which site it targets). Six branches cover every
combination:

| | staging (`qbt-staging.fdsaservices.com`) | production (`fdsa-query-builder.alzheimersdata.org`) |
|---|---|---|
| **vanilla** | [`vanilla-staging`](../../tree/vanilla-staging) | [`vanilla-production`](../../tree/vanilla-production) |
| **aha** | [`aha-staging`](../../tree/aha-staging) | [`aha-production`](../../tree/aha-production) |
| **grip** | [`grip-staging`](../../tree/grip-staging) | [`grip-production`](../../tree/grip-production) |

### Flavors

- **vanilla** — the pre-fix baseline. A stock Chromium window with a
  "Query Builder" bookmark and homepage set, and **no lockdown policy at
  all** (no `URLBlocklist`/`URLAllowlist` — a normal, unrestricted browser).
  No downloads-permission fix, no AKS network-mount fix. This is a
  historical/reference starting point, not something actively deployed.
- **aha** — the current, fixed build (URL lockdown via `policy.json`,
  downloads-permission-relaxing service, downloads mounted outside
  `/config` to avoid the AKS network-mount startup slowdown). Built and
  pushed to our own registry (`qbtcontainers.azurecr.io`), then mirrored to
  AHA's own registry (Aridhia, `acrwesteuropeaddi.azurecr.io`) — the only
  flavor that pushes to a second registry.
- **grip** — the *same target site* as `aha`, and it carries `aha`'s fixes,
  but it has its own **additional** fix on top: Query Builder's "Download
  Results" button uses the File System Access API (not a normal browser
  download), which was landing files inside the container's internal
  storage instead of the shared mount. The fix (`QB_DOWNLOAD_DIR`, seeding
  the picker's remembered directory, removing a base-image policy file that
  was silently conflicting with `policy.json`) is `grip-*`-only — see
  `README-GRIP.md`/`README-GRIP-PROD.md` on those branches. Distribution is
  also different: grip's environment is air-gapped, so instead of a second
  registry push the image is `docker save`d to a tar file and loaded
  manually on the other side.

**`aha-*` and `grip-*` are not interchangeable code** — `grip-*` is a
superset (aha's fixes plus grip's own), not a repackaging of the same
build. A fix made on `aha-*` still needs to be ported into `grip-*` on top
of grip's own changes, and a `grip-*`-only fix has no reason to go to
`aha-*` at all.

### Environments

Every flavor comes in `-staging` and `-production` variants, which differ in
exactly three things:
- `policy.json`'s `HomepageLocation` / `RestoreOnStartupURLs`
- `root/defaults/Bookmarks`' bookmark `url` (and its `name`, e.g.
  `Query Builder v3 (staging)` vs `Query Builder v3` — bump this on every
  release so the bookmark bar shows what's actually running)
- the registry/tar tag (`qbtstagingcontainer` vs `qbtcontainer`, or
  `fdsa_qbt_staging` vs `fdsa_qbt` on Aridhia)

---

## Making a fix

**There is no shared/templated code across branches** — each of the six
branches is an independent copy, and `grip-*` carries `aha-*`'s fixes plus
its own on top (see [Flavors](#flavors)). That means porting is
direction-sensitive, not a blanket "copy everywhere":

- A fix to shared/base behavior (locked to Query Builder, the permission-fix
  service, the AKS mount-outside-`/config` fix) belongs on `aha-staging`
  first, then ported to `aha-production` **and** into `grip-staging`/
  `grip-production` on top of grip's own changes.
- A fix specific to grip's downloads-location/File System Access behavior
  belongs only on `grip-staging`, then ported to `grip-production` — it has
  no reason to touch `aha-*`.
- `vanilla-*` is a historical snapshot, not an active deployment — only
  touch it if the baseline itself needs correcting, not as part of a
  routine fix.

There's no tooling for this yet — `git cherry-pick` across branches works if
the surrounding code hasn't diverged too far; otherwise it's a manual diff
and reapply. Keep this in mind before "quickly" fixing something on one
branch and moving on — it isn't live anywhere else until it's ported.

**Known outstanding issue (grip):** `chrome://policy` reports `URLAllowlist`
— Status: **Error** on the grip build, unrelated to the downloads fix and
never diagnosed (likely the bare `mailto`/`mailto:` entries and a duplicated
`discover.alzheimersdata.org` entry in `policy.json`). See
`grip-production`'s `README-GRIP-PROD.md` before that build carries real
traffic.

---

## Background / design docs

These live only here on `main` since they're not specific to any one
branch:

- [`README-STAG.md`](README-STAG.md) — client-facing write-up of the
  downloads-outside-`/config` fix (the AKS network-mount startup issue and
  why it was fixed the way it was). The fix itself lives on `aha-*`/`grip-*`;
  this is the incident/rationale doc.
- [`idledetectionreport.md`](idledetectionreport.md) — notes on detecting
  session idle time via `xprintidle`, for potential idle-timeout automation.
  Not implemented yet.
- [`qbcontainerstoragemultiuser.md`](qbcontainerstoragemultiuser.md) — design
  discussion on the single-session-per-container model and what true
  multi-user isolation would require. No decision made yet; read this before
  someone asks "can multiple people use one container at once?".

---

## Where this is headed

This repo is being handed off to `alzheimersdata-org/QB-Containerized-App`,
which will carry the same branch structure. If you're picking this project
up, the six branches above and their individual READMEs are the working
entry points — `main` is only ever documentation.
