# Query Builder browser container — vanilla baseline.
#
# A stock Chromium window (toolbar, Home button, back/forward/reload) preset
# with a "Query Builder" bookmark and homepage. No URL lockdown, no
# downloads-permission fix, no AKS network-mount fix — this is the pre-fix
# starting point the aha-*/grip-* branches build on.
#
# Based on the jlesage Chromium image (noVNC web layer).

FROM jlesage/chromium:latest

# Homepage + bookmark only. No URLBlocklist/URLAllowlist here, so this is a
# normal, unrestricted browser — see policy.json.
COPY policy.json /etc/chromium/policies/managed/policy.json
COPY policy.json /etc/chromium-browser/policies/managed/policy.json

# Seed the "Query Builder" bookmark + the init hook that places it.
COPY root/ /
RUN chmod +x /etc/cont-init.d/60-seed-bookmarks.sh

ENV APP_NAME="Query Builder"
ENV WEB_LISTENING_PORT="4443"

EXPOSE 4443
