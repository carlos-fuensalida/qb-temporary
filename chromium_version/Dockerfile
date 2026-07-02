# Query Builder browser container — normal window, locked to one place.
#
# A standard Chromium window (toolbar, Home button, back/forward/reload — so a
# user can always recover) that can ONLY reach Query Builder and its SSO login
# domain. Enforcement is a Chromium managed policy (policy.json), not kiosk mode.
#
# Based on the jlesage Chromium image, which uses a noVNC web layer (no WebCodecs
# / secure-context requirement, unlike the KasmVNC image).

FROM jlesage/chromium:latest

# Install the managed policy. Copied to both common Chromium policy locations so
# it applies regardless of the image's package layout. Verify at chrome://policy.
COPY policy.json /etc/chromium/policies/managed/policy.json
COPY policy.json /etc/chromium-browser/policies/managed/policy.json

# Seed the Bookmarks file with a correct MD5 checksum so Chromium accepts it
RUN cat > /defaults/gen-bookmarks.py << 'PYEOF'
import hashlib, json, os

ts = "13286954536000000"

roots = {
    "bookmark_bar": {
        "children": [{
            "date_added": ts,
            "guid": "1a2b3c4d-1234-4000-8000-000000000001",
            "id": "3",
            "name": "Query Builder",
            "type": "url",
            "url": "https://qbt-staging.fdsaservices.com/qbt/"
        }],
        "date_added": ts,
        "date_modified": ts,
        "guid": "00000000-0000-4000-a000-000000000001",
        "id": "1",
        "name": "Bookmarks bar",
        "type": "folder"
    },
    "other": {
        "children": [],
        "date_added": ts,
        "date_modified": "0",
        "guid": "00000000-0000-4000-a000-000000000002",
        "id": "2",
        "name": "Other bookmarks",
        "type": "folder"
    },
    "synced": {
        "children": [],
        "date_added": ts,
        "date_modified": "0",
        "guid": "00000000-0000-4000-a000-000000000003",
        "id": "4",
        "name": "Mobile bookmarks",
        "type": "folder"
    }
}

def md5_node(node, h):
    h.update(node["id"].encode())
    h.update(node["guid"].encode())
    h.update(node["name"].encode("utf-16-le"))
    h.update(node["type"].encode())
    if node["type"] == "url":
        h.update(node["url"].encode())
    for child in node.get("children", []):
        md5_node(child, h)

h = hashlib.md5()
for key in ("bookmark_bar", "other", "synced"):
    md5_node(roots[key], h)
checksum = h.hexdigest()

doc = {"checksum": checksum, "roots": roots, "version": 1}
out = json.dumps(doc, indent=3, ensure_ascii=False)
print(out)
PYEOF

RUN printf '#!/bin/sh\nPROFILE_DIR=/config/chromium/Default\nmkdir -p "$PROFILE_DIR"\npython3 /defaults/gen-bookmarks.py > "$PROFILE_DIR/Bookmarks"\n' \
    > /etc/cont-init.d/60-seed-bookmarks.sh && \
    chmod +x /etc/cont-init.d/60-seed-bookmarks.sh

ENV APP_NAME="Query Builder"
ENV WEB_LISTENING_PORT="4443"

EXPOSE 4443
