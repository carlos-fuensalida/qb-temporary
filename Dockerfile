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

# The base image ships its OWN policy files into that same directory:
# managed_policies.json and a managed_policies.json.bk sample. Chromium
# merges every file in policies/managed (the extension is irrelevant — the
# .bk is live policy too), so both collide with ours. Observed on a deployed
# container via chrome://policy:
#   - DefaultDownloadDirectory = /config/Downloads, "OK, Superseding"
#     (from managed_policies.json) — this is what made the file dialog open
#     inside the container's local /config instead of the shared mount.
#   - ManagedBookmarks "Warning, Conflict" — the .bk sample defines its own
#     Google/Youtube/Chrome-links bookmarks against ours.
# Rather than add competing values and depend on undefined merge precedence
# between two files, drop the base image's files so policy.json is the
# single source of truth. Its one key worth keeping,
# ExtensionInstallForcelist, is folded into policy.json instead (extension
# pnbbookneacpggbngfmhfggennhigonh — shipped by the base image; don't drop
# it from policy.json without first checking what it does);
# DefaultBrowserSettingEnabled was already set there.
RUN rm -f /etc/chromium/policies/managed/managed_policies.json \
          /etc/chromium/policies/managed/managed_policies.json.bk \
          /etc/chromium-browser/policies/managed/managed_policies.json \
          /etc/chromium-browser/policies/managed/managed_policies.json.bk

# Seed the "Query Builder" bookmark + install the init hook that places it,
# plus a service that relaxes download file permissions (Chromium forces 0600).
# Also overrides the app service's `params` file to add --test-type whenever
# --no-sandbox is used, suppressing Chromium's "unsupported command-line flag"
# infobar (the base image has no env var to append custom Chromium args).
# 61-seed-downloads-dir.sh points the native GTK file dialog's "Downloads"
# shortcut at /downloads too — DownloadDirectory (below) only covers
# Chromium's own silent downloads, not that dialog's default location.
COPY root/ /
RUN chmod +x /etc/cont-init.d/59-set-download-dir.sh \
             /etc/cont-init.d/60-seed-bookmarks.sh \
             /etc/cont-init.d/61-seed-downloads-dir.sh \
             /etc/cont-init.d/62-seed-picker-dir.sh \
             /etc/services.d/fix-downloads/run \
             /etc/services.d/app/params

# Downloads live outside /config on purpose. The base image's startup init
# recursively chowns all of /config to USER_ID/GROUP_ID on every launch; when
# the mounted downloads volume is a network share (e.g. Azure Files/CIFS),
# that recursive chown turns into a per-file network round trip and can add
# minutes to container start. Keeping /downloads outside /config means that
# chown only ever walks local disk, and downloads are redirected here via the
# DownloadDirectory policy in policy.json.
RUN mkdir -p /downloads

ENV APP_NAME="Query Builder"
ENV WEB_LISTENING_PORT="4443"

EXPOSE 4443
