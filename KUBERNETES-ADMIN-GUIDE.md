# Query Builder (v4) container — Kubernetes deployment notes for cluster admins

**Purpose:** make the "Download Results" button in Query Builder save to the
shared file system, not into the container's own `/config` storage.

Three settings must all be right. If any one is missing, downloads silently
land in the wrong place, even with the v4 image:

1. The **correct v4 image** is the one actually running.
2. The pod sets **`QB_DOWNLOAD_DIR`** to the path where the share is mounted.
3. The pod starts with a **fresh `/config`** (no profile left from an earlier run).

---

## 1. Use the right image

| Environment | Source branch | Bookmark label shown in the browser |
|---|---|---|
| Staging | `grip-staging` | `Query Builder v4 (staging)` |
| Production | `grip-production` | `Query Builder v4` |

- Do **not** build from `aha-staging` / `aha-production` (lowercase). Those
  branches do not contain the download fix.
- Do not build from `claude/downloads-folder-location-imjnz1` or
  `claude/grip-prod-image`. They are older (v3).
- **Give every build a unique tag** (for example `:grip-v4-20261009`), or
  deploy by digest. Re-using `:grip` lets a node keep serving a cached old
  image when `imagePullPolicy: IfNotPresent`. If you must re-use a tag, set
  `imagePullPolicy: Always`.
- Air-gapped clusters: `docker load` the tar, retag, and push it to the
  internal registry. The Deployment must reference that internal tag.

## 2. Set `QB_DOWNLOAD_DIR` and mount the share at the same path

`QB_DOWNLOAD_DIR` (default `/downloads`) is the one variable that drives
Chromium's download policy, the save dialog's "Downloads" shortcut, the
folder the save dialog opens at, and the permission-fix service.

- The mount path and `QB_DOWNLOAD_DIR` **must be identical** and are
  **case-sensitive** (`/config/Downloads` is not `/config/downloads`).
- Recommended on Kubernetes: mount the share **outside** `/config`
  (`/downloads`). The base image recursively `chown`s all of `/config` on
  every start, which is very slow on a network share (Azure Files/CIFS).
- If the share must sit inside `/config` (the GRIP layout), set
  `QB_DOWNLOAD_DIR=/config/Downloads` and mount it there. Expect slower
  startup as the share grows.

## 3. Start with a fresh `/config`

The save dialog's starting folder is seeded only when
`/config/chromium/Default/Preferences` does **not** exist. Back `/config`
with an **`emptyDir`**, so every pod start is a fresh profile. Do not back
it with a PVC. If a PVC is unavoidable, delete or recreate it for this
rollout.

The profile (cookies and the like) is lost on pod restart. This is
acceptable here because users sign in again through SSO.

---

## Example Deployment (share outside `/config`)

Replace the placeholders: `<REGISTRY>`, `<TAG>`, `<PVC_OR_SHARE>`, and the
IDs (they should match the owner of the share).

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qb
spec:
  replicas: 1
  selector:
    matchLabels: { app: qb }
  template:
    metadata:
      labels: { app: qb }
    spec:
      containers:
        - name: qb
          image: <REGISTRY>/qbtcontainer:<TAG>   # unique tag, see section 1
          imagePullPolicy: IfNotPresent          # use Always if the tag is re-used
          ports:
            - containerPort: 4443
          env:
            - { name: USER_ID,  value: "10001" }
            - { name: GROUP_ID, value: "1001" }
            - { name: QB_DOWNLOAD_DIR, value: "/downloads" }  # == mountPath below
          volumeMounts:
            - { name: shared,  mountPath: /downloads }   # the shared file system
            - { name: config,  mountPath: /config }      # fresh profile each start
            - { name: shm,     mountPath: /dev/shm }
      volumes:
        - name: shared
          persistentVolumeClaim: { claimName: <PVC_OR_SHARE> }
        - name: config
          emptyDir: {}
        - name: shm
          emptyDir: { medium: Memory, sizeLimit: 2Gi }   # equivalent of --shm-size 2g
```

For the inside-`/config` layout, change two lines: `QB_DOWNLOAD_DIR` to
`/config/Downloads` and the `shared` mountPath to `/config/Downloads`.

The container needs outbound access only to the allow-listed Query Builder
and SSO hosts. The lockdown is enforced inside the browser by `policy.json`.

---

## Verification checklist (after rollout)

Run these against the new pod:

```bash
# 1. Right settings are in the pod spec
kubectl get pod <pod> -o yaml | grep -E "image:|QB_DOWNLOAD_DIR|mountPath"

# 2. Startup scripts picked up the variable and seeded a fresh profile
kubectl logs <pod> | grep -E "set-download-dir|seed-picker-dir"
#   expect: [set-download-dir] downloads directory is <DIR>
#   expect: [seed-picker-dir] seeded /config/chromium/Default/Preferences ...
#   "already exists; leaving the profile alone" => /config was reused (section 3)

# 3. Only our policy file is present (no base-image policy conflict)
kubectl exec <pod> -- ls /etc/chromium/policies/managed/
#   expect: policy.json only
```

In the browser session:

- The bookmark bar shows **`Query Builder v4`** (or `... v4 (staging)`).
  A `v3` label means the old image is running.
- `chrome://policy`: `DownloadDirectory` and `DefaultDownloadDirectory` both
  show `<DIR>`, with no "Superseding" status.
- Run a query, click **Download Results**, and confirm the save dialog opens
  at the shared drive. Then confirm the file is on the share.

## Known issue (unrelated to downloads)

`chrome://policy` reports `URLAllowlist: Error` on the grip build, probably
from the bare `mailto` / `mailto:` entries or a duplicated
`https://discover.alzheimersdata.org` line in `policy.json`. The lockdown may
not be fully enforced until this is fixed. Raise it with the image
maintainers before production traffic.

## If it still lands in the wrong place

Send the maintainers the output of the three commands above, plus a
screenshot of `chrome://policy` and the Deployment YAML.
