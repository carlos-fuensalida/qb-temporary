#!/bin/sh
# Make the file save dialog open at /downloads instead of the container's
# home dir (/config) the very first time a user clicks "Download Results".
#
# Why this is separate from the DownloadDirectory policy: Query Builder saves
# through the File System Access API (window.showSaveFilePicker) rather than
# a plain browser download — the dialog's title bar carries Chromium's
# "Warning: this site can see edits you make" wording, which is that API's
# picker. That API ignores DownloadDirectory/DefaultDownloadDirectory
# entirely. Its starting folder comes from either a startIn hint the web page
# passes (Query Builder passes none, and that is the app's call to make, not
# ours) or, failing that, the directory the origin last picked. With no
# remembered directory, Chromium falls back to $HOME — /config — which is
# what users were seeing.
#
# Chromium records that memory as a content-settings exception under
# file_system_last_picked_directory, verified by reading it out of a
# container where a user had saved to /downloads once. Seeding it up front
# means a brand new container behaves as if that had already happened.
#
# Only seeds a profile that does not exist yet. Chromium creates Preferences
# on first run, so writing it beforehand lets Chromium fill in every other
# default around what we set. Patching an existing Preferences would mean
# editing nested JSON with sed (no jq or python in this image), which is not
# worth the risk of corrupting a live profile — and an existing profile has
# already remembered a directory of its own anyway.
#
# NOTE: this only takes effect on a fresh /config. A container recreated
# against an existing /config volume keeps whatever that profile already
# remembered — see README-GRIP.md for the `docker rm -f -v` step.

PROFILE_DIR=/config/chromium/Default
PREFS="$PROFILE_DIR/Preferences"

if [ -e "$PREFS" ]; then
  echo "[seed-picker-dir] $PREFS already exists; leaving the profile alone"
  exit 0
fi

# Resolved by 59-set-download-dir.sh, which runs first.
DOWNLOAD_DIR="$(cat /var/run/qb-download-dir 2>/dev/null || echo /downloads)"

# Timestamps are Chromium's internal format (microseconds since 1601). The
# values are copied from a real captured entry; they only record when the
# directory was last picked, so a fixed point in the past is fine.
LAST_MODIFIED="13431206074976115"
TIMESTAMP="13431206074976105"

# Every origin this image is pointed at across environments. Listing them all
# keeps this file out of the per-environment edit list in README.md — one
# image behaves correctly whichever URL policy.json is built for.
ENTRY='{"last_modified":"'"$LAST_MODIFIED"'","setting":{"default-id":{"display-name":"downloads","path":"'"$DOWNLOAD_DIR"'","path-type":0,"timestamp":"'"$TIMESTAMP"'"}}}'

mkdir -p "$PROFILE_DIR"
cat > "$PREFS" <<EOF
{"profile":{"content_settings":{"exceptions":{"file_system_last_picked_directory":{"https://qbt-staging.fdsaservices.com:443,*":$ENTRY,"https://fdsa-query-builder.alzheimersdata.org:443,*":$ENTRY,"https://qbt-pre-prod.fdsaservices.com:443,*":$ENTRY}}}}}
EOF

echo "[seed-picker-dir] seeded $PREFS with $DOWNLOAD_DIR as the last-picked directory"
