# Query Builder Container — AHA Staging

A Chromium browser in a Docker container that opens **Query Builder**
(`https://qbt-staging.fdsaservices.com/qbt/`) and is locked to it. Downloads and
uploads use the shared drive mounted into the container.

Image: `qbtcontainers.azurecr.io/qbtstagingcontaineraha:latest`

## Run

```bash
docker run -d \
  --name=qb \
  --restart=unless-stopped \
  --shm-size 2g \
  -e USER_ID=10001 -e GROUP_ID=1001 \
  -p 4443:4443 \
  -v /mnt/vm-shared-storage:/downloads:rw \
  qbtcontainers.azurecr.io/qbtstagingcontaineraha:latest
```

Then open `http://<host-ip>:4443`.

- `/mnt/vm-shared-storage` is the shared drive's path on the host.
- `USER_ID` / `GROUP_ID` should match the owner of the shared drive
  (`id <username>` on the host).

## Changing the download directory (`QB_DOWNLOAD_DIR`)

The shared drive is mounted at `/downloads` by default. To mount it somewhere
else, set `QB_DOWNLOAD_DIR` to the container-side path and mount the drive at
that same path:

```bash
  -e QB_DOWNLOAD_DIR=/config/Downloads \
  -v /mnt/vm-shared-storage:/config/Downloads:rw \
```

`QB_DOWNLOAD_DIR` must be an absolute path and must match the mount. Keep the
default (`/downloads`, outside `/config`) for network shares: the base image
re-owns all of `/config` on every start, which gets slow on a large share.

## Updating or replacing the container

Get the latest image (`docker pull qbtcontainers.azurecr.io/qbtstagingcontaineraha:latest`), then remove the running container
together with its own `/config` volume and run the command above again:

```bash
docker rm -f -v qb
```

`-v` removes only the container's own volume, not the shared drive.

## Build, tag, and push

```bash
docker login -u read-write -p <password> qbtcontainers.azurecr.io

docker build -t qbtcontainers.azurecr.io/qbtstagingcontaineraha:latest .
docker push qbtcontainers.azurecr.io/qbtstagingcontaineraha:latest
```

### AHA's registry (Aridhia)

The image is also mirrored to AHA's own registry:

```bash
docker login -u read-write -p <SOURCE_REGISTRY_PASSWORD> qbtcontainers.azurecr.io
docker pull qbtcontainers.azurecr.io/qbtstagingcontaineraha:latest
docker tag qbtcontainers.azurecr.io/qbtstagingcontaineraha:latest acrwesteuropeaddi.azurecr.io/0a6ed49f-321c-4320-b746-6b72de4f2640/fdsa_qbt_staging:latest
docker login -u fdsa-qbt -p <TARGET_REGISTRY_PASSWORD> acrwesteuropeaddi.azurecr.io
docker push acrwesteuropeaddi.azurecr.io/0a6ed49f-321c-4320-b746-6b72de4f2640/fdsa_qbt_staging:latest
```
