# QB Container — Staging

This project implements a Docker container for Query Builder (Staging environment).
The GUI of the application is accessed through a modern web browser (no installation or configuration needed on the client side).

**NOTE:** This is the URL we target with the container: `https://qbt-staging.fdsaservices.com/qbt/`

## Overview

### ADDI Query Builder Container (Staging)

The ADDI Query Builder Container is a Docker container that runs a dedicated **Chromium** web browser that is fixed to access the ADDI Query Builder **staging** service located at: `https://qbt-staging.fdsaservices.com`.

The container runs a noVNC web layer that provides a virtual desktop of the Chromium browser. The browser shows a **normal window with toolbar** (Home button, back/forward, reload) — not a kiosk — so a user who gets stuck can always recover without restarting the container. Lockdown is enforced by a Chromium managed policy: every URL outside the allowlist is blocked at the browser engine.

The design of the ADDI Query Builder Container is to allow an end user/researcher to access only the ADDI Query Builder service, and to only allow them to save query results to a network/locally defined file system.

## Quick Start

**NOTE:** The image is called `qbtcontainers.azurecr.io/qbtstagingcontainer:latest` and it lives in one of our private registries. Please contact us to get your Docker login credentials to be able to pull the image.

**NOTE:** The Docker command provided in this quick start is given as an example and parameters should be adjusted to your need.

Launch the QB docker container with the following command:

```bash
docker run -d \
    --name=qb \
    -p 4443:4443 \
    -v /files/shared/drive:/config/Downloads:rw \
    qbtcontainers.azurecr.io/qbtstagingcontainer:latest
```

Where:
- `/files/shared/drive`: This is where the application stores downloaded files.

Browse to `http://your-host-ip:4443` to access the QBT GUI.

## Usage

```bash
docker run [-d] \
    --name=qb \
    [-e <VARIABLE_NAME>=<VALUE>]... \
    [-v <HOST_DIR>:<CONTAINER_DIR>[:PERMISSIONS]]... \
    [-p <HOST_PORT>:<CONTAINER_PORT>]... \
    qbtcontainers.azurecr.io/qbtstagingcontainer:latest
```

## Aridhia and Registries

To push to Aridhia we need to pull from our registry and push to Aridhia:

```bash
docker login -u read-write -p <SOURCE_REGISTRY_PASSWORD> qbtcontainers.azurecr.io
docker pull qbtcontainers.azurecr.io/qbtstagingcontainer:latest
docker tag qbtcontainers.azurecr.io/qbtstagingcontainer:latest acrwesteuropeaddi.azurecr.io/0a6ed49f-321c-4320-b746-6b72de4f2640/fdsa_qbt_staging:latest
docker login -u fdsa-qbt -p <TARGET_REGISTRY_PASSWORD> acrwesteuropeaddi.azurecr.io
docker push acrwesteuropeaddi.azurecr.io/0a6ed49f-321c-4320-b746-6b72de4f2640/fdsa_qbt_staging:latest
```

## Parameters

| Parameter | Description |
|-----------|-------------|
| `-d` | Run the container in the background. If not set, the container runs in the foreground. |
| `-e` | Pass an environment variable to the container. See the Environment Variables section for more details. |
| `-v` | Set a volume mapping (allows to share a folder/file between the host and the container). See the Data Volumes section for more details. |
| `-p` | Set a network port mapping (exposes an internal container port to the host). See the Ports section for more details. |

## Deployment Considerations

As an example this is the `docker-compose.yml`:

```yaml
services:
  qbt:
    image: qbtcontainers.azurecr.io/qbtstagingcontainer:latest
    restart: unless-stopped
    ports:
      - "4443:4443"
    cap_add:
      - SYS_ADMIN
    environment:
      - SECURE_CONNECTION=0
      - WEB_LISTENING_PORT=4443
    volumes:
      - /files/shared/drive:/config/Downloads:rw
```

## Data Volumes

The following table describes data volumes used by the container. The mappings are set via the `-v` parameter. Each mapping is specified with the following format: `<HOST_DIR>:<CONTAINER_DIR>[:PERMISSIONS]`.

| Container path | Permissions | Description |
|----------------|-------------|-------------|
| `/config/Downloads` | rw | This is where downloaded files are stored. |

## Ports

| Port | Protocol | Mapping to host | Description |
|------|----------|-----------------|-------------|
| 4443 | TCP | Optional | Port to access the application's GUI via the web interface. Mapping to the host is optional if access through the web interface is not wanted. For a container not using the default bridge network, the port can be changed with the `WEB_LISTENING_PORT` environment variable. |

## User/Group IDs

When using data volumes (`-v` flags), permissions issues can occur between the host and the container. To avoid any problem, you can specify the user the application should run as by passing the user ID and group ID via the `USER_ID` and `GROUP_ID` environment variables.

To find the right IDs to use, issue the following command on the host, with the user owning the data volume on the host:

```bash
id <username>
```

Which gives an output like this one:

```
uid=1000(myuser) gid=1000(myuser) groups=1000(myuser),4(adm),24(cdrom),27(sudo),46(plugdev),113(lpadmin)
```

The value of `uid` (user ID) and `gid` (group ID) are the ones that you should give the container.

## Accessing the GUI

Assuming that container's ports are mapped to the same host's ports, the graphical interface of the application can be accessed via a web browser:

```
http://<HOST IP ADDR>:4443
```

## Security

By default, access to the application's GUI is done over an unencrypted connection (HTTP).

Secure connection can be enabled via the `SECURE_CONNECTION` environment variable. When enabled, the application's GUI is served over HTTPS, and all HTTP accesses are automatically redirected to HTTPS.

To get zero TLS errors for the user:
- **Real trusted cert on the container** matching the hostname users reach it by: set `SECURE_CONNECTION=1` and mount `web-fullchain.pem` + `web-privkey.pem` in `/config/certs`.
- **Or TLS at the TRE gateway**: set `SECURE_CONNECTION=0` and let the platform's trusted HTTPS reach the user. (Often the least effort.)
- **Self-signed will warn the user** — avoid for production.

### Certificates

| Container Path | Purpose | Content |
|----------------|---------|---------|
| `/config/certs/web-privkey.pem` | HTTPS connection encryption | Web server's private key |
| `/config/certs/web-fullchain.pem` | HTTPS connection encryption | Web server's certificate, bundled with any root and intermediate certificates |

### Web Authentication

Access to the application's GUI via a web browser can be protected with a login page. When web authentication is enabled, users have to provide valid credentials, otherwise access is denied.

Web authentication can be enabled by setting the `WEB_AUTHENTICATION` environment variable to `1`.

**NOTE:** Secure connection must also be enabled to use web authentication. See the Security section for more details.

#### Configuring Users Credentials

Two methods can be used to configure users credentials:

1. **Via container environment variables** — quick way to configure a single user:
   - `WEB_AUTHENTICATION_USERNAME`
   - `WEB_AUTHENTICATION_PASSWORD`

2. **Via password database** — more secure, supports multiple users. The database is at `/config/webauth-htpasswd` inside the container (same format as Apache htpasswd files, bcrypt hashed).

   Users are managed via the `webauth-user` tool included in the container:
   - Add a user: `docker exec -ti <container name or id> webauth-user add <username>`
   - Update a user: `docker exec -ti <container name or id> webauth-user update <username>`
   - Remove a user: `docker exec <container name or id> webauth-user del <username>`
   - List users: `docker exec <container name or id> webauth-user user`

## Environment Variables

To customize some properties of the container, the following environment variables can be passed via the `-e` parameter (one for each variable). Value of this parameter has the format `<VARIABLE_NAME>=<VALUE>`.

| Variable | Description | Default |
|----------|-------------|---------|
| `USER_ID` | ID of the user the application runs as. | `1000` |
| `GROUP_ID` | ID of the group the application runs as. | `1000` |
| `SUP_GROUP_IDS` | Comma-separated list of supplementary group IDs of the application. | (no value) |
| `LANG` | Set the locale (e.g. `en_US.UTF-8`). | `en_US.UTF-8` |
| `TZ` | TimeZone used by the container. | `Etc/UTC` |
| `KEEP_APP_RUNNING` | When set to `1`, the application is automatically restarted when it crashes or terminates. | `0` |
| `CONTAINER_DEBUG` | Set to `1` to enable debug logging. | `0` |
| `DISPLAY_WIDTH` | Width (in pixels) of the application's window. | `1920` |
| `DISPLAY_HEIGHT` | Height (in pixels) of the application's window. | `1080` |
| `DARK_MODE` | When set to `1`, dark mode is enabled for the application. | `0` |
| `WEB_AUTHENTICATION` | When set to `1`, the GUI is protected via a login page. Requires `SECURE_CONNECTION=1`. | `0` |
| `WEB_AUTHENTICATION_USERNAME` | Optional username for web authentication (single user). | (no value) |
| `WEB_AUTHENTICATION_PASSWORD` | Optional password for web authentication (single user). | (no value) |
| `SECURE_CONNECTION` | When set to `1`, an encrypted connection is used to access the GUI. | `0` |
| `SECURE_CONNECTION_VNC_METHOD` | Method used for the secure VNC connection. Possible values: `SSL` or `TLS`. | `SSL` |
| `SECURE_CONNECTION_CERTS_CHECK_INTERVAL` | Interval (in seconds) at which the system checks for certificate changes. `0` disables the check. | `60` |
| `WEB_LISTENING_PORT` | Port used by the web server to serve the UI. Set to `-1` to disable HTTP/HTTPS access. | `4443` |

## URL Lockdown

The browser is locked to the Query Builder staging environment and its SSO/login domains via a Chromium managed policy (`policy.json`). All other URLs are blocked — whether reached by typing, a link, a redirect, or a popup.

The address bar remains visible and usable, but any non-allowed destination shows a "blocked" page. This keeps the recovery controls (Home, back/forward, reload) available to the user while preventing them from leaving the allowed domains.

Allowed domains can be reviewed and extended in `policy.json` (`URLAllowlist`). If a login flow bounces through an unexpected domain, open `chrome://policy` in the session to verify policies are active, then add the missing domain to the allowlist.

## Verify the lock took effect

Inside the session open `chrome://policy` — it lists the active policies. Confirm `URLBlocklist`, `URLAllowlist`, `ShowHomeButton`, and `HomepageLocation` are present. If they are missing, the policy file did not land at a path this image's Chromium reads; check `chrome://policy` and adjust the `COPY` path in the Dockerfile.

## Still open: one session per user

This container is one browser = one session. Each user getting their own session still depends on **one instance being launched per user** — the platform question for the Azure/TRE team.
