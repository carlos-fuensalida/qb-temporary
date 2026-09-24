# QB Container — grip (staging)

A dedicated Chromium browser, delivered as a Docker container, that opens
**Query Builder** and is locked to it, for the grip deployment. Target site:
`https://qbt-staging.fdsaservices.com/qbt/`.

This is the **grip** flavor: it carries its own fix (not `aha-*`'s) for a
real bug where Query Builder's "Download Results" button — which uses the
File System Access API, not a normal browser download — was saving files
into the container's internal storage instead of the shared mount. Root
cause, the fix, build steps, and verification are all in
**[README-GRIP.md](README-GRIP.md) — read that before building or deploying
this branch.**

`aha-*` and `grip-*` are different fixes for different environments, not the
same code — see `main`'s README for the full branch map.

---

## Quick reference

- Build/run/verify: see [README-GRIP.md](README-GRIP.md).
- Push to the registry, share pull credentials, and deploy as root or as a
  specific user/group ID: see
  [howtodeploystaging.md](howtodeploystaging.md).
- Registry: this branch is not pushed to a second registry the way `aha-*`
  is pushed to Aridhia. Grip's environment is air-gapped — the image is
  tagged `qbtcontainers.azurecr.io/qbtstagingcontainer:grip`, then
  `docker save`d to a tar and transferred/loaded manually. Exact commands
  are in README-GRIP.md's build section.
- Known open issue: `chrome://policy` on this build reports `URLAllowlist`
  — Status: **Error** (unrelated to the downloads fix, never diagnosed;
  likely culprits are the bare `mailto`/`mailto:` entries and a duplicated
  `discover.alzheimersdata.org` entry in `policy.json`). See the
  "Known outstanding issue" section of `grip-production`'s
  `README-GRIP-PROD.md` for detail before this carries real traffic.
