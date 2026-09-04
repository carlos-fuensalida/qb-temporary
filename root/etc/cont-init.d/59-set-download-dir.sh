#!/bin/sh
# Resolve where downloads should go, once, for everything else to use.
#
# Which path the shared drive is mounted at is a DEPLOYMENT decision, not
# something this image should dictate:
#   - The AKS automation workspaces mount it at /downloads, deliberately
#     outside /config (see README.md — the base image recursively chowns all
#     of /config on every start, and over a network share that becomes a
#     per-file round trip and minutes of startup time).
#   - GRIP mounts it at /config/Downloads instead.
# Hardcoding either one breaks the other, so take it from the environment:
#
#   docker run -e QB_DOWNLOAD_DIR=/config/Downloads -v <share>:/config/Downloads:rw ...
#
# Default stays /downloads so existing deployments are unaffected.
#
# The resolved value is written to a file rather than relied on as an env var
# downstream, because the fix-downloads service under /etc/services.d is not
# guaranteed to inherit the container environment the way cont-init.d scripts
# do. A file works for both without depending on with-contenv being present.

DIR="${QB_DOWNLOAD_DIR:-/downloads}"

# Reject anything that isn't a plain absolute path: the value is substituted
# into JSON and into a sed expression below, so a stray quote, backslash or
# sed delimiter would corrupt the policy file rather than fail loudly.
case "$DIR" in
  /*) ;;
  *) echo "[set-download-dir] QB_DOWNLOAD_DIR must be an absolute path, got '$DIR'; falling back to /downloads"
     DIR=/downloads ;;
esac
case "$DIR" in
  *'"'*|*'\'*|*'|'*|*'$'*)
     echo "[set-download-dir] QB_DOWNLOAD_DIR contains unsupported characters, got '$DIR'; falling back to /downloads"
     DIR=/downloads ;;
esac

mkdir -p "$DIR"
printf '%s\n' "$DIR" > /var/run/qb-download-dir

# Chromium's managed policy is copied in at build time with /downloads baked
# in, so rewrite both keys to the resolved path. Matching on the key rather
# than the old value means this stays correct if the default ever changes.
for f in /etc/chromium/policies/managed/policy.json \
         /etc/chromium-browser/policies/managed/policy.json; do
  [ -f "$f" ] || continue
  sed -i \
    -e 's|\("DownloadDirectory"[[:space:]]*:[[:space:]]*\)"[^"]*"|\1"'"$DIR"'"|' \
    -e 's|\("DefaultDownloadDirectory"[[:space:]]*:[[:space:]]*\)"[^"]*"|\1"'"$DIR"'"|' \
    "$f"
done

echo "[set-download-dir] downloads directory is $DIR"

if [ "$DIR" != "${DIR#/config/}" ]; then
  echo "[set-download-dir] NOTE: $DIR is inside /config, which the base image"
  echo "[set-download-dir] recursively chowns on every start. If the share is a"
  echo "[set-download-dir] network filesystem this can slow startup considerably"
  echo "[set-download-dir] as it fills up — see README.md."
fi
