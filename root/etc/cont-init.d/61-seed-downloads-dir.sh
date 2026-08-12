#!/bin/sh
# Point the native GTK file dialog's "Downloads" shortcut at the real
# downloads mount (/downloads), not the container's default $HOME/Downloads.
#
# Chromium's own *automatic* silent downloads already land in /downloads via
# the DownloadDirectory policy (policy.json) — that part was fixed already.
# This script fixes the *other*, unrelated mechanism: the GTK file chooser's
# own "Downloads" bookmark/default location, which comes from XDG user-dirs
# and is not touched by that Chromium policy at all. Without this, manually
# saving/opening a file (e.g. Ctrl+S, "Save Page As") still opens into
# $HOME/Downloads inside /config, not the shared network drive — so users
# see an empty/unrelated folder instead of where their downloads actually are.
#
# HOME for this image is /config (same convention already used by
# 60-seed-bookmarks.sh, which writes to /config/chromium/... directly).
# Runs on every start, before Chromium launches, so it's correct even on a
# completely fresh /config volume. Any recursive chown the base image does
# afterwards covers these files the same as everything else under /config.

CONFIG_HOME=/config/.config
mkdir -p "$CONFIG_HOME"

# Point XDG's Downloads dir at the real mount. Also disable
# xdg-user-dirs-update so it doesn't silently regenerate this file back to
# the default $HOME/Downloads on some later run.
cat > "$CONFIG_HOME/user-dirs.dirs" <<'EOF'
XDG_DOWNLOAD_DIR="/downloads"
EOF
cat > "$CONFIG_HOME/user-dirs.conf" <<'EOF'
enabled=False
EOF

# Belt-and-suspenders: also seed the GTK file-chooser sidebar bookmark
# directly, since some dialogs read the bookmarks list rather than
# XDG_DOWNLOAD_DIR.
mkdir -p "$CONFIG_HOME/gtk-3.0"
BOOKMARKS="$CONFIG_HOME/gtk-3.0/bookmarks"
touch "$BOOKMARKS"
grep -qxF 'file:///downloads Downloads' "$BOOKMARKS" || \
  echo 'file:///downloads Downloads' >> "$BOOKMARKS"
