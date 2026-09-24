# How to Deploy the GRIP Staging Image

This document covers the full loop for the **grip-staging** image: pushing
it to our registry and the two supported ways to run the container — as
**root** and as a **specific user/group ID**. It's meant to sit next to
[README-GRIP.md](README-GRIP.md) (which covers building the image and the
downloads-location fix in detail) rather than repeat it — build there,
deploy here.

Image: `qbtcontainers.azurecr.io/qbtstagingcontainer:grip`
Target site: `https://qbt-staging.fdsaservices.com/qbt/`

---

## 1. Push the image to the registry

Build the image first (see [README-GRIP.md](README-GRIP.md#building-the-image)
if you haven't):

```bash
docker build -t qbtcontainers.azurecr.io/qbtstagingcontainer:grip .
```

Log in and push:

```bash
docker login qbtcontainers.azurecr.io
docker push qbtcontainers.azurecr.io/qbtstagingcontainer:grip
```

If grip's target VM is air-gapped and can't reach the registry at all, skip
the push and use the `docker save`/`.tar` path in
[README-GRIP.md](README-GRIP.md#save-to-a-tar) instead — the two delivery
methods are alternatives, not both required.

---

## 2. Deploying the container

Both deployment modes below use the same image and the same downloads-mount
choice — only `USER_ID`/`GROUP_ID` change. Pick the mount layout that
matches your environment first (see
[README-GRIP.md — Choosing where downloads go](README-GRIP.md#choosing-where-downloads-go)):

- **GRIP (share mounted inside `/config`):** set
  `QB_DOWNLOAD_DIR=/config/Downloads` and mount the share at that same path.
- **AKS automation workspaces (share mounted outside `/config`):** leave
  `QB_DOWNLOAD_DIR` unset (defaults to `/downloads`) and mount the share at
  `/downloads`.

`QB_DOWNLOAD_DIR` is always shown explicitly below, even where it just
repeats the default — that keeps this doc in sync with
[README-GRIP.md](README-GRIP.md) and
[README-STAG.md](README-STAG.md), where the same variable is documented, so
none of the three drift out of agreement on what to set. If you ever add or
change a downloads-related variable, update it in all three places.

### 2a. Deploy as root

Set `USER_ID=0 GROUP_ID=0` to run the container's `app` user with root's
numeric IDs — the base image (`jlesage/chromium`) has no separate "run as
root" switch; this is how you get it. This sidesteps host-side file
ownership questions on the mounted share entirely, at the cost of the
container process running as root. Use this only where the target
host/VM's security policy allows it.

```bash
docker run -d \
  --name=qb \
  --restart=unless-stopped \
  --shm-size 2g \
  -e USER_ID=0 -e GROUP_ID=0 \
  -e QB_DOWNLOAD_DIR=/config/Downloads \
  -p 4443:4443 \
  -v /mnt/vm-shared-storage:/config/Downloads:rw \
  qbtcontainers.azurecr.io/qbtstagingcontainer:grip
```

### 2b. Deploy as a specific user/group ID

The recommended, least-privilege default. Set `USER_ID`/`GROUP_ID` to match
whoever owns the shared drive on the host, so downloaded files land with
usable, non-root ownership. Run `id <username>` on the host to find the
right values — `10001`/`1001` below are the values already in use on the
current GRIP staging VM; confirm before reusing them elsewhere.

```bash
docker run -d \
  --name=qb \
  --restart=unless-stopped \
  --shm-size 2g \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -e QB_DOWNLOAD_DIR=/config/Downloads \
  -p 4443:4443 \
  -v /mnt/vm-shared-storage:/config/Downloads:rw \
  qbtcontainers.azurecr.io/qbtstagingcontainer:grip
```

For the AKS-style layout (share outside `/config`), swap the two `-e
QB_DOWNLOAD_DIR`/`-v` lines above for:

```bash
  -e QB_DOWNLOAD_DIR=/downloads \
  -v /files/shared/drive:/downloads:rw \
```

### Removing an existing container first

If a container named `qb` is already running (e.g. switching it from one
mode to the other, or deploying a new build), remove it — and its anonymous
`/config` volume — before running the command above, exactly as
[README-GRIP.md](README-GRIP.md#2-remove-the-currently-running-container-and-its-config-volume)
describes:

```bash
docker rm -f -v qb
```

`-v` only removes the container's anonymous Docker volumes; it does not
touch the bind-mounted shared drive.

---

## 3. Verify

Use the verification steps in
[README-GRIP.md — How to verify](README-GRIP.md#how-to-verify) and the
numbered checks in its "Deploying" section (mount type, policy conflict
gone, picker seed applied, actual download lands on the shared drive,
startup time, bookmark label) — they apply the same way regardless of
whether the container is running as root or as a mapped user/group ID.
