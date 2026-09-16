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

Same as the [base image's own quick-start](https://github.com/jlesage/docker-chromium)
— nothing project-specific added:

```bash
docker build -t qbt-vanilla-production .

docker run -d \
  --name=qb \
  -p 5800:5800 \
  -v /files/shared/drive:/config:rw \
  qbt-vanilla-production
```

Browse to `http://<host-ip>:5800`.

---

## What's different from `aha-*`/`grip-*`

This branch is the stock `jlesage/chromium` image plus exactly two changes:
the homepage/landing URL and the seeded bookmark. Everything else —
including things `aha-*`/`grip-*` change — is untouched:

- No `URLBlocklist`/`URLAllowlist` in `policy.json` — any site is reachable,
  not just Query Builder and its SSO domains.
- Default port (`5800`), not `4443` — `aha-*`/`grip-*` override
  `WEB_LISTENING_PORT`, this branch doesn't.
- Default volume scope — mount the whole `/config` (as the base image's own
  docs show), not a downloads-only mount. Downloads land at
  `/config/Downloads`, Chromium's own default, with no
  `/downloads`-outside-`/config` fix and no permission-relaxing service.
  That fix only matters once downloads are on a network-mounted drive
  (e.g. AKS/Azure Files) — see `main`'s README for why.
- No `--shm-size` override in the run command.

This branch is a historical/reference starting point, not where day-to-day
fixes land — see `main` for the branch map and where to make changes.
