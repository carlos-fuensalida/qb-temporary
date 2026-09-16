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
- **grip** — the *same* fixed code and the *same* target site as `aha`, just
  packaged differently: grip's environment is air-gapped, so instead of a
  second registry push the image is `docker save`d to a tar file and loaded
  manually on the other side. No credentials/registry access needed for that
  hop.

`aha` and `grip` differ **only** in how the image gets distributed — the
Dockerfile, `policy.json`, and everything under `root/` are meant to stay in
sync between `aha-staging`/`grip-staging` and between
`aha-production`/`grip-production`.

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
branches is an independent copy. A fix normally starts on `aha-staging`
(fastest to test against), then has to be **manually ported** to the other
five branches (`aha-production`, `grip-staging`, `grip-production`, and,
where relevant, `vanilla-staging`/`vanilla-production`). There's no
tooling for this yet — `git cherry-pick` across branches works if the
surrounding code hasn't diverged too far; otherwise it's a manual diff and
reapply. Keep this in mind before "quickly" fixing something on one branch
and moving on — it isn't live anywhere else until it's ported.

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
