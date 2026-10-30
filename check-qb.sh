#!/usr/bin/env bash
# check-qb.sh — diagnose the Query Builder container's download configuration.
#
# Read-only apart from one write test, which creates and immediately removes a
# single zero-byte file in the download directory.
#
# Usage:  ./check-qb.sh [container-name]     (default: qb)
#
# Exit status: 0 = no failures, 1 = at least one FAIL.

set -uo pipefail

CONTAINER="${1:-qb}"
FAILED=0
WARNED=0

bold=$(printf '\033[1m'); red=$(printf '\033[31m'); grn=$(printf '\033[32m')
ylw=$(printf '\033[33m'); dim=$(printf '\033[2m'); rst=$(printf '\033[0m')
[ -t 1 ] || { bold=""; red=""; grn=""; ylw=""; dim=""; rst=""; }

section() { printf '\n%s== %s ==%s\n' "$bold" "$1" "$rst"; }
pass()    { printf '  %s[ OK ]%s %s\n'   "$grn" "$rst" "$1"; }
warn()    { printf '  %s[WARN]%s %s\n'   "$ylw" "$rst" "$1"; WARNED=$((WARNED+1)); }
fail()    { printf '  %s[FAIL]%s %s\n'   "$red" "$rst" "$1"; FAILED=$((FAILED+1)); }
info()    { printf '  %s       %s%s\n'   "$dim" "$1" "$rst"; }

dex() { docker exec "$CONTAINER" "$@" 2>/dev/null; }

# ---------------------------------------------------------------- container --
section "Container"

if ! command -v docker >/dev/null 2>&1; then
  fail "docker command not found — run this on the Docker host."
  exit 1
fi

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  fail "No container named '$CONTAINER'."
  info "Containers present: $(docker ps -a --format '{{.Names}}' | tr '\n' ' ')"
  info "Pass the right name:  $0 <container-name>"
  exit 1
fi

STATE=$(docker inspect -f '{{.State.Status}}' "$CONTAINER")
IMAGE=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER")
STARTED=$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER")

[ "$STATE" = "running" ] && pass "State: running" || fail "State: $STATE (expected running)"
info "Image:   $IMAGE"
info "Started: $STARTED"

# ------------------------------------------------------------------ version --
section "Version"

BOOKMARK=$(dex sh -c 'grep -o "\"name\": \"Query Builder[^\"]*\"" /defaults/Bookmarks | head -1 | cut -d: -f2-' \
           | sed 's/^ *"//; s/"$//')
if [ -n "$BOOKMARK" ]; then
  pass "Bookmark label: $BOOKMARK"
  info "This is the label users see in the bookmark bar — it is how you tell builds apart."
else
  warn "Could not read the bookmark label from /defaults/Bookmarks."
fi

# v8 ships these three scripts; a rolled-back build has only 60-seed-bookmarks.
MISSING=""
for s in 59-set-download-dir.sh 61-seed-downloads-dir.sh 62-seed-picker-dir.sh; do
  dex test -f "/etc/cont-init.d/$s" || MISSING="$MISSING $s"
done
if [ -z "$MISSING" ]; then
  pass "Download-location fixes present (59, 61, 62)."
else
  fail "Image is missing:$MISSING"
  info "This image predates the download fixes (or is a rolled-back build such as v7)."
  info "The save dialog will open at /config and downloads may not reach the share."
fi

if dex test -e /etc/chromium/policies/managed/managed_policies.json; then
  fail "Base-image policy file managed_policies.json is still present."
  info "It sets DefaultDownloadDirectory=/config/Downloads and overrides this image's setting."
else
  pass "Base-image policy files removed — policy.json is the only policy source."
fi

# --------------------------------------------------------- download directory --
section "Download directory"

DIR=$(dex cat /var/run/qb-download-dir | tr -d '\r\n')
ENVDIR=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER" \
         | sed -n 's/^QB_DOWNLOAD_DIR=//p')

if [ -n "$DIR" ]; then
  pass "Resolved download directory: $DIR"
  [ -n "$ENVDIR" ] && info "From QB_DOWNLOAD_DIR=$ENVDIR" \
                   || info "QB_DOWNLOAD_DIR not set — using the built-in default."
else
  DIR="/downloads"
  warn "Could not read /var/run/qb-download-dir; assuming the default $DIR."
fi

POLICY=$(dex sh -c 'grep -o "\"DownloadDirectory\"[^,]*" /etc/chromium/policies/managed/policy.json' \
         | sed 's/.*: *"//; s/"$//')
if [ "$POLICY" = "$DIR" ]; then
  pass "Chromium policy agrees: DownloadDirectory = $POLICY"
else
  fail "Chromium policy says '$POLICY' but the resolved directory is '$DIR'."
fi

if dex test -d "$DIR"; then
  pass "Directory exists inside the container."
else
  fail "Directory $DIR does not exist inside the container."
fi

# ------------------------------------------------------------------- mounts --
section "Mounts"

mapfile -t MOUNT_LINES < <(docker inspect -f '{{range .Mounts}}{{.Type}}|{{.Source}}|{{.Destination}}{{println}}{{end}}' "$CONTAINER")

for line in "${MOUNT_LINES[@]}"; do
  [ -z "$line" ] && continue
  IFS='|' read -r t s d <<<"$line"
  info "$(printf '%-7s %s -> %s' "$t" "$s" "$d")"
done

# Longest-prefix match: which mount actually backs the download directory?
BEST_D=""; BEST_T=""; BEST_S=""
for line in "${MOUNT_LINES[@]}"; do
  [ -z "$line" ] && continue
  IFS='|' read -r t s d <<<"$line"
  case "$DIR" in
    "$d"|"$d"/*)
      if [ "${#d}" -gt "${#BEST_D}" ]; then BEST_D="$d"; BEST_T="$t"; BEST_S="$s"; fi ;;
  esac
done

if [ -z "$BEST_D" ]; then
  fail "$DIR is not on any mount — it is plain container storage."
  info "Downloads saved there are LOST when the container is replaced."
  info "Mount the share at $DIR, or set QB_DOWNLOAD_DIR to a path on a mount."
elif [ "$BEST_T" = "bind" ]; then
  pass "$DIR is backed by a bind mount of $BEST_S (at $BEST_D)."
else
  fail "$DIR is backed by a Docker $BEST_T named '$BEST_S' (at $BEST_D), not the shared drive."
  info "A Docker volume is container-managed storage, not your network share."
fi

# Nested mounts. A Docker volume at /config with the share mounted at
# /config/Downloads is the normal shape and is NOT a problem, so only nesting
# inside a bind mount (a real share) is reported — that is what hides part of
# the share and sends downloads to the wrong volume.
NEST_FAIL=""; NEST_WARN=""
for inner in "${MOUNT_LINES[@]}"; do
  [ -z "$inner" ] && continue
  IFS='|' read -r it is_ id <<<"$inner"
  for outer in "${MOUNT_LINES[@]}"; do
    [ -z "$outer" ] && continue
    IFS='|' read -r ot os od <<<"$outer"
    [ "$id" = "$od" ] && continue
    [ "$ot" = "bind" ] || continue
    case "$id" in
      "$od"/*)
        if [ "$od" = "$BEST_D" ] || [ "$id" = "$BEST_D" ]; then
          NEST_FAIL="${NEST_FAIL}$id inside $od; "
        else
          NEST_WARN="${NEST_WARN}$id inside $od; "
        fi ;;
    esac
  done
done

if [ -n "$NEST_FAIL" ]; then
  fail "A mount is nested inside the share holding your downloads: $NEST_FAIL"
  info "The inner mount hides that folder on the share, so downloads never reach it."
  info "Mount the share ONCE, and point QB_DOWNLOAD_DIR at a folder inside it."
elif [ -n "$NEST_WARN" ]; then
  warn "Mount nested inside another share: $NEST_WARN"
  info "Not affecting downloads, but the inner mount hides that folder on the outer share."
else
  pass "No problematic nested mounts."
fi

# -------------------------------------------------------------- permissions --
section "Permissions"

UID_SET=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER" | sed -n 's/^USER_ID=//p')
GID_SET=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER" | sed -n 's/^GROUP_ID=//p')
UID_SET=${UID_SET:-1000}; GID_SET=${GID_SET:-1000}
info "USER_ID=$UID_SET  GROUP_ID=$GID_SET"

OWNER=$(dex stat -c '%u:%g %a' "$DIR")
[ -n "$OWNER" ] && info "$DIR owner:mode = $OWNER"

PROBE=".qb-write-check.$$"
if docker exec -u "$UID_SET:$GID_SET" "$CONTAINER" sh -c "touch '$DIR/$PROBE' 2>/dev/null"; then
  pass "The app user ($UID_SET:$GID_SET) can write to $DIR."
  docker exec "$CONTAINER" rm -f "$DIR/$PROBE" >/dev/null 2>&1
else
  fail "The app user ($UID_SET:$GID_SET) CANNOT write to $DIR."
  info "Downloads will fail with 'Permission denied'."
  info "Set USER_ID/GROUP_ID to the owner of the share on the host:"
  info "    stat -c '%u %g' <host-share-path>"
fi

# ------------------------------------------------------------- save dialog --
section "Save dialog starting folder"

SEED=$(docker logs "$CONTAINER" 2>&1 | grep 'seed-picker-dir' | tail -1)
case "$SEED" in
  *"seeded"*)
      pass "Picker directory seeded — the save dialog opens at the download folder."
      info "$SEED" ;;
  *"already exists"*)
      fail "Picker seed was SKIPPED: an existing Chromium profile was reused."
      info "$SEED"
      info "The save dialog will keep opening wherever it last opened."
      info "Fix: docker rm -f -v $CONTAINER   (the -v matters) and start it again." ;;
  *)
      warn "No seed-picker-dir message in the logs."
      info "Either this image predates the fix, or the logs have rotated." ;;
esac

XDG=$(dex sh -c 'cat /config/.config/user-dirs.dirs 2>/dev/null || cat /config/xdg/config/user-dirs.dirs 2>/dev/null')
case "$XDG" in
  *"$DIR"*) pass "Sidebar Downloads shortcut points at $DIR." ;;
  "")       warn "No XDG user-dirs file found (sidebar shortcut may be missing)." ;;
  *)        warn "Sidebar shortcut does not point at $DIR: $XDG" ;;
esac

# -------------------------------------------------------------- startup log --
section "Startup messages"

docker logs "$CONTAINER" 2>&1 | grep -E 'set-download-dir|seed-downloads-dir|fix-downloads' \
  | tail -8 | sed 's/^/  /' || true
docker logs "$CONTAINER" 2>&1 | grep -q 'is inside /config' && \
  info "Note: the download directory is inside /config, which the base image re-owns on every start. Expect slower starts as the share grows."

# ----------------------------------------------------------------- summary --
section "Summary"

if [ "$FAILED" -eq 0 ] && [ "$WARNED" -eq 0 ]; then
  printf '  %sAll checks passed.%s\n' "$grn" "$rst"
elif [ "$FAILED" -eq 0 ]; then
  printf '  %s%s warning(s), no failures.%s\n' "$ylw" "$WARNED" "$rst"
else
  printf '  %s%s failure(s)%s and %s warning(s). See [FAIL] lines above.%s\n' \
    "$red" "$FAILED" "$rst" "$WARNED" "$rst"
fi

printf '\n  To test end to end: open http://<host>:4443, run a query, click\n'
printf '  Download Results, and confirm the dialog opens at:\n    %s\n' "$DIR"
printf '  Then confirm the file appears on the share from the host.\n\n'

[ "$FAILED" -eq 0 ]
