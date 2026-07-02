# Query Builder browser container — normal window, locked to one place.
#
# A standard Chromium window (toolbar, Home button, back/forward/reload — so a
# user can always recover) that can ONLY reach Query Builder and its allowed
# SSO/login domains. Enforcement is a Chromium managed policy (policy.json)
# applied at the browser engine — no proxy or firewall needed.
#
# Based on the jlesage Chromium image (noVNC web layer).

FROM jlesage/chromium:latest

# The lockdown: a Chromium managed policy. URLBlocklist ["*"] blocks everything
# and URLAllowlist re-permits only the QB + SSO domains, whether reached by
# typing, a link, a redirect, or a popup. Copied to BOTH common policy paths so
# it applies regardless of the image's Chromium package layout.
# Verify it took effect at chrome://policy inside the session.
COPY policy.json /etc/chromium/policies/managed/policy.json
COPY policy.json /etc/chromium-browser/policies/managed/policy.json

# Seed the "Query Builder" bookmark + install the init hook that places it.
COPY root/ /
RUN chmod +x /etc/cont-init.d/60-seed-bookmarks.sh

ENV APP_NAME="Query Builder"
ENV WEB_LISTENING_PORT="4443"

EXPOSE 4443
