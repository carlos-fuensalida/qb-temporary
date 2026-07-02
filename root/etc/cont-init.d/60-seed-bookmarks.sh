#!/bin/sh
# Seed the Chromium profile with the "Query Builder" bookmark. Runs at every
# start (before Chromium launches) so the bookmark is present even on a fresh
# /config volume. The file ships with a valid MD5 checksum, so no generation
# (and no python) is needed at runtime.
PROFILE_DIR=/config/chromium/Default
mkdir -p "$PROFILE_DIR"
cp /defaults/Bookmarks "$PROFILE_DIR/Bookmarks"
