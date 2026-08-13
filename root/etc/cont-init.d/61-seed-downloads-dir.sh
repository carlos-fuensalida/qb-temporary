#!/bin/sh
# Point the native GTK file dialog's "Downloads" shortcut at the real
# downloads mount (/downloads), not the container's default $HOME/Downloads.
#
# Chromium's own *automatic* silent downloads already land in /downloads via
# the DownloadDirectory policy (policy.json) — that part was fixed already.
# This script fixes the *other*, unrelated mechanism: the GTK file chooser's
# own "Downloads" bookmark/default location, which comes from XDG user-dirs
# and is not touched by that Chromium policy at all. Without this, manually
# saving/opening a file (e.g. Ctrl+S, "Save Page As") opens into the
# container's home dir (/config) instead of the shared network drive, so
# users see an unrelated folder — and anything saved there lands in the
# container's internal volume rather than on the shared drive.
#
# Why several target directories: GTK reads these files from
# $XDG_CONFIG_HOME, which the base image may relocate (it keeps a
# /config/xdg tree) rather than leaving at the $HOME/.config default. Writing
# to the runtime-resolved value *and* the known candidates keeps this correct
# regardless of how the base image sets it, instead of hardcoding one guess.
#
# Runs on every start, before Chromium launches, so it's correct even on a
# completely fresh /config volume. 85-take-config-ownership.sh runs after
# this and chowns /config, so these files get the right ownership.

# Candidate config roots, de-duplicated below:
#   1. the runtime-resolved XDG_CONFIG_HOME (authoritative when set)
#   2. $HOME/.config (the spec default when XDG_CONFIG_HOME is unset)
#   3. /config/.config — the app user's home is /config, and cont-init runs
#      as root ($HOME=/root), so #2 does NOT cover this. Must be explicit.
#   4. /config/xdg/config (the base image's relocated XDG tree)
CANDIDATES="${XDG_CONFIG_HOME:-} ${HOME:-/config}/.config /config/.config /config/xdg/config"

SEEDED=""
for CFG in $CANDIDATES; do
  # Skip empties and anything already handled.
  [ -n "$CFG" ] || continue
  case " $SEEDED " in *" $CFG "*) continue ;; esac
  SEEDED="$SEEDED $CFG"

  mkdir -p "$CFG/gtk-3.0" || continue

  # Point XDG's Downloads dir at the real mount, and disable
  # xdg-user-dirs-update so it can't silently regenerate this back to the
  # default $HOME/Downloads on a later run.
  printf '%s\n' 'XDG_DOWNLOAD_DIR="/downloads"' > "$CFG/user-dirs.dirs"
  printf '%s\n' 'enabled=False' > "$CFG/user-dirs.conf"

  # Seed the GTK file-chooser sidebar bookmark too, since some dialogs read
  # the bookmarks list rather than XDG_DOWNLOAD_DIR. Append rather than
  # overwrite: the base image may ship its own bookmarks here (e.g. /app).
  BOOKMARKS="$CFG/gtk-3.0/bookmarks"
  touch "$BOOKMARKS"
  grep -qxF 'file:///downloads Downloads' "$BOOKMARKS" || \
    printf '%s\n' 'file:///downloads Downloads' >> "$BOOKMARKS"

  echo "[seed-downloads-dir] seeded $CFG"
done
