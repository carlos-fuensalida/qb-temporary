# QB Container — vanilla (production)

The baseline Query Builder browser container, prior to any of the fixes
carried on the `aha-*`/`grip-*` branches. A stock Chromium window (toolbar,
Home button, back/forward, reload) preset with a "Query Builder" bookmark
and homepage pointing at production.

**No URL lockdown.** Unlike `aha-*`/`grip-*`, there is no
`URLBlocklist`/`URLAllowlist` — this is a normal, unrestricted browser that
happens to open on Query Builder.

Target site: `https://fdsa-query-builder.alzheimersdata.org/qbt/`

---

## Build & run

```bash
docker build -t qbt-vanilla-production .

docker run -d \
  --name=qb \
  --shm-size 2g \
  -p 4443:4443 \
  -v /files/shared/drive:/config/Downloads:rw \
  qbt-vanilla-production
```

Browse to `http://<host-ip>:4443`.

---

## What's different from `aha-*`/`grip-*`

- No `URLBlocklist`/`URLAllowlist` in `policy.json` — any site is reachable,
  not just Query Builder and its SSO domains.
- Downloads use the base image's default `/config/Downloads` mount, not the
  `/downloads`-outside-`/config` fix. That fix only matters once downloads
  are on a network-mounted drive (e.g. AKS/Azure Files) — see `main`'s
  README for why.
- No downloads file-permission-relaxing service — Chromium's default
  `0600` download permissions apply as-is.

This branch is a historical/reference starting point, not where day-to-day
fixes land — see `main` for the branch map and where to make changes.
