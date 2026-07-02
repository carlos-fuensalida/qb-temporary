# QBT Chromium container

A dedicated Chromium (based on [`jlesage/chromium`](https://github.com/jlesage/docker-chromium))
that opens Query Builder and is locked to it. You view it in your own browser
via the image's built-in noVNC web layer.

- **Normal browser window** — toolbar, Home button, back/forward, reload — so a
  user who gets stuck can always recover without restarting the container.
- **Lockdown via Chromium managed policy** (`policy.json`), enforced at the
  browser engine: every URL outside `URLAllowlist` is blocked, whether reached
  by typing, a link, a redirect, or a popup. **No proxy or firewall involved.**

## Build & run

```bash
docker build -t qbt-kiosk .

docker run -d --name=qb \
  --cap-add=SYS_ADMIN \
  --shm-size 2g \
  -p 4443:4443 \
  -v /files/shared/drive:/config/Downloads:rw \
  qbt-kiosk
```

Or with compose:

```bash
docker compose up -d --build
```

Then browse to <http://your-host-ip:4443>.

- `--cap-add=SYS_ADMIN` lets Chromium's sandbox work under this base image.
- `--shm-size 2g` avoids Chromium crashes on heavy pages.
- `/config/Downloads` (capital D) is where Chromium saves downloads — mount it
  to a host/network path.

## Change the URL / allowed hosts

**`policy.json` is the single place to edit.** To repoint the kiosk or permit
another domain:

1. Add the host to `URLAllowlist` in `policy.json`.
2. If it's the new landing page, update `HomepageLocation` and
   `RestoreOnStartupURLs`.
3. Rebuild.

`URLAllowlist` entries match the host **and its subdomains**. The default
landing page is set by the policy's `RestoreOnStartupURLs`; the Home button
goes to `HomepageLocation`.

## Verify the lock took effect

Inside the session, open `chrome://policy` — it lists the active policies.
Confirm `URLBlocklist`, `URLAllowlist`, `ShowHomeButton`, and `HomepageLocation`
are present. If they're missing, the policy file didn't land at a path this
image's Chromium reads — check the `COPY` paths in the `Dockerfile`.

## Watch out: auth redirect hosts

Federated logins often bounce through extra domains that aren't obvious up
front. If a login stalls, the blocked host will show a "blocked" page — note it
(or check `chrome://policy`), add it to `URLAllowlist`, and rebuild. Microsoft
sign-in, for example, may also touch `login.microsoft.com`, `login.live.com`,
`aadcdn.msftauth.net`, `logincdn.msauth.net`.

## Security / TLS

Access is over HTTP by default. For zero TLS warnings for the user, either set
`SECURE_CONNECTION=1` and mount a real trusted cert at `/config/certs`
(`web-fullchain.pem` + `web-privkey.pem`), or leave `SECURE_CONNECTION=0` and
terminate HTTPS at an upstream gateway. Self-signed certs will warn the user.
