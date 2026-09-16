# testing-qbt — connectivity test container

This branch is **not** the Query Builder app. It's a throwaway diagnostic
image, `nginx:alpine` serving one static page over plain HTTP on port
`4443` (the same port grip uses), for isolating a connectivity problem from
the app itself.

## When to use this

You've `docker load`ed `grip-staging`/`grip-production`, `docker ps` shows
the container `Up`, `curl` from the same host gets *something*, but a
browser hitting `localhost:4443` fails (e.g. `ERR_CONNECTION_RESET`). Before
digging further into the grip image, load and run this container instead:

- **This container also unreachable** → the problem is environmental (host
  networking, a proxy/VPN in front of the browser, the VM's firewall, a
  wrong "localhost" — see below), not the grip image. Stop debugging the
  app image and debug the network path instead.
- **This container reachable, grip is not** → the problem is inside the
  grip image/app itself. Most likely candidate: the jlesage/chromium base
  image serves its web UI over **HTTPS** by default (`SECURE_CONNECTION`),
  while this test container is plain HTTP — if grip only fails on `http://`
  but works on `https://`, that's your answer. Also check `docker logs qb`
  and `docker exec qb sh -c "ss -tlnp"` to confirm the app inside actually
  bound the port.

Also worth checking regardless of which container is running: confirm the
browser making the request is running on the **exact same host** as the
Docker daemon. In a nested remote-desktop setup, a browser one hop further
out than expected will treat `localhost` as itself, not the docker host.

## Step 1 — Build (on a VM with internet + Docker)

```bash
git clone https://github.com/carlos-fuensalida/qb-temporary.git
cd qb-temporary
git checkout testing-qbt

docker build -t qbtcontainers.azurecr.io/qbtcontainer:testing .
```

## Step 2 — Save to a tar

```bash
docker save -o qbt-testing.tar qbtcontainers.azurecr.io/qbtcontainer:testing
```

This image is a few MB (`nginx:alpine`), nowhere near grip's ~1 GB — the tar
transfer itself is not the thing being tested here.

## Step 3 — Transfer to the air-gapped VM

Same channel you already use for the grip tar.

## Step 4 — Load on the air-gapped VM

```bash
docker load -i qbt-testing.tar
docker images | grep qbtcontainer
```

## Step 5 — Run

Stop the grip container first if it's holding port 4443:

```bash
docker rm -f qb
```

Then run the test container on the same port:

```bash
docker run -d --name=qbt-test --restart=unless-stopped -p 4443:4443 \
  qbtcontainers.azurecr.io/qbtcontainer:testing
```

## Step 6 — Test

From the **same terminal/host** as the `docker run` above:

```bash
curl -v http://localhost:4443
```

Then, from the browser you were using to reach the grip container, navigate
to `http://localhost:4443` explicitly (include the scheme).

Record which of the two — curl, browser — succeeds or fails, and compare
against the same two tests against the grip container. That comparison is
the diagnostic; report both back.

## Step 7 — Clean up

```bash
docker rm -f qbt-test
docker run -d --name=qb ... # your original grip run command
```
