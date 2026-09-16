# QB Container — grip (production)

A dedicated Chromium browser, delivered as a Docker container, that opens
**Query Builder** and is locked to it, for the grip deployment. Target site:
`https://fdsa-query-builder.alzheimersdata.org/qbt/`.

This is the **grip** flavor: it carries its own fix (not `aha-*`'s) for a
real bug where Query Builder's "Download Results" button — which uses the
File System Access API, not a normal browser download — was saving files
into the container's internal storage instead of the shared mount. Full
build/delivery runbook, verification steps, and a known open issue to check
before this carries real traffic: **[README-GRIP-PROD.md](README-GRIP-PROD.md)
— read that before building or deploying this branch.** Background on the
root cause: [README-GRIP.md](README-GRIP.md).

`aha-*` and `grip-*` are different fixes for different environments, not the
same code — see `main`'s README for the full branch map.

---

## Quick reference

- Build/save/transfer/load, verification, and the known `URLAllowlist`
  policy error to check before go-live: see
  [README-GRIP-PROD.md](README-GRIP-PROD.md).
- Registry: not pushed to a second registry the way `aha-*` is pushed to
  Aridhia. Grip's environment is air-gapped — the image is tagged
  `qbtcontainers.azurecr.io/qbtcontainer:grip`, then `docker save`d to a tar
  and transferred/loaded manually.
