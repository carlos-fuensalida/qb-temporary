# Query Builder browser container — vanilla baseline.
#
# The jlesage/chromium base image, unmodified except for two things: the
# homepage (which URL it opens to) and a seeded "Query Builder" bookmark.
# No port override, no volume reshaping, no extra services — everything
# else is exactly what jlesage/chromium ships. This is the pre-fix starting
# point the aha-*/grip-* branches build on.
#
# Based on the jlesage Chromium image (noVNC web layer):
# https://github.com/jlesage/docker-chromium

FROM jlesage/chromium:latest

# Homepage + bookmark only. No URLBlocklist/URLAllowlist here, so this is a
# normal, unrestricted browser — see policy.json. Copied to both policy
# paths so it applies regardless of this image's Chromium package layout.
COPY policy.json /etc/chromium/policies/managed/policy.json
COPY policy.json /etc/chromium-browser/policies/managed/policy.json

# Seed the "Query Builder" bookmark + the init hook that places it.
COPY root/ /
RUN chmod +x /etc/cont-init.d/60-seed-bookmarks.sh
