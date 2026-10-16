# Query Builder Container — GRIP Staging

A Chromium browser in a Docker container that opens **Query Builder**
(`https://qbt-staging.fdsaservices.com/qbt/`) and is locked to it. Downloads and
uploads use the shared drive mounted into the container.

Image: `qbtcontainers.azurecr.io/qbtstagingcontainergrip:latest`

## Run

```bash
docker run -d \
  --name=qb \
  --restart=unless-stopped \
  --shm-size 2g \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -e QB_DOWNLOAD_DIR=/config/Downloads \
  -p 4443:4443 \
  -v /mnt/vm-shared-storage:/config/Downloads:rw \
  qbtcontainers.azurecr.io/qbtstagingcontainergrip:latest
```

Then open `http://<host-ip>:4443`.

- `/mnt/vm-shared-storage` is the shared drive's path on the host.
- `USER_ID` / `GROUP_ID` should match the owner of the shared drive
  (`id <username>` on the host).
- `QB_DOWNLOAD_DIR` and the container-side mount path must be the same.

## Updating or replacing the container

Get the latest image (`docker pull qbtcontainers.azurecr.io/qbtstagingcontainergrip:latest`,
or `docker load -i <file>.tar` if it was delivered as a tar), then remove the
running container together with its own `/config` volume and run the command
above again:

```bash
docker rm -f -v qb
```

`-v` removes only the container's own volume, not the shared drive.

## Note

The share is mounted inside `/config`, which the base image re-owns on every
start. On a large network share this can slow startup; if it does, mount the
share outside `/config` instead (`-e QB_DOWNLOAD_DIR=/downloads` and
`-v <share>:/downloads:rw`).
