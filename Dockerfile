# Minimal network/connectivity test container — NOT the qb app.
#
# Purpose: isolate "can a browser on this VM reach localhost:<port> for a
# container we just docker-loaded" from every other moving part in the
# grip-staging/grip-production image (jlesage/chromium, noVNC, HTTPS on the
# web UI, policy.json, the downloads mount). If this container is reachable
# but grip-production is not, the problem is inside the grip image/app. If
# this container is ALSO unreachable, the problem is environmental — host
# networking, a proxy, or the VM's firewall — not the app.
#
# Deliberately serves plain HTTP (no TLS) on the same port grip uses
# (4443), so a plain `curl`/browser hit at http://localhost:4443 is a valid
# test with no protocol ambiguity — unlike jlesage/chromium's web UI, which
# defaults to HTTPS and will reset a plaintext request on the same port.
FROM nginx:alpine

COPY index.html /usr/share/nginx/html/index.html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 4443
