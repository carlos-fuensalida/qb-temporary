# Query Builder (v6) container — Kubernetes deployment notes for cluster admins

**Purpose:** make the "Download Results" button in Query Builder save to the
shared file system, not into the container's own `/config` storage, and make
the file-upload dialog open at the share too.

Three settings must all be right. If any one is missing, downloads and uploads
silently go to the wrong place:

1. The **correct v6 image** is the one actually running.
2. The pod sets **`QB_DOWNLOAD_DIR`** to the path where the share is mounted.
3. The pod starts with a **fresh `/config`** (no profile left from an earlier run).

---

## 1. Use the right image

| Environment | Source branch | Bookmark label shown in the browser |
|---|---|---|
| Staging | `grip-staging` | `Query Builder v6 (staging)` |
| Production | `grip-production` | `Query Builder v6` |

- Staging image: `qbtcontainers.azurecr.io/qbtstagingcontainergrip:latest`
- Production image: `qbtcontainers.azurecr.io/qbtcontainergrip:latest`
- The images are tagged `:latest`, so set `imagePullPolicy: Always` (or leave
  it unset: Kubernetes then defaults to `Always` for `:latest`). With
  `IfNotPresent`, a node keeps serving a cached old image after a new push.
  After a new push, run `kubectl rollout restart deployment/qb` so the pods
  pull it, or deploy by digest to pin an exact build.
- Air-gapped clusters: `docker load` the tar, retag, and push it to the
  internal registry. The Deployment must reference that internal tag.

## 2. Set `QB_DOWNLOAD_DIR` and mount the share at the same path

`QB_DOWNLOAD_DIR` (default `/downloads`) is the one variable that drives
Chromium's download policy, the save dialog's "Downloads" shortcut, the
folder the save and upload dialogs open at, and the permission-fix service.

- The mount path and `QB_DOWNLOAD_DIR` **must be identical** and are
  **case-sensitive** (`/config/Downloads` is not `/config/downloads`).
- Recommended on Kubernetes: mount the share **outside** `/config`
  (`/downloads`). The base image recursively `chown`s all of `/config` on
  every start, which is very slow on a network share (Azure Files/CIFS).
- If the share must sit inside `/config` (the GRIP layout), set
  `QB_DOWNLOAD_DIR=/config/Downloads` and mount it there. Expect slower
  startup as the share grows.

## 3. Start with a fresh `/config`

The save and upload dialogs' starting folder is seeded only when
`/config/chromium/Default/Preferences` does **not** exist. Back `/config`
with an **`emptyDir`**, so every pod start is a fresh profile. Do not back
it with a PVC. If a PVC is unavoidable, delete or recreate it for this
rollout.

The profile (cookies and the like) is lost on pod restart. This is
acceptable here because users sign in again through SSO.

---

## Example Deployment (share outside `/config`)

Replace the placeholders: `<PVC_OR_SHARE>` and the IDs (they should match
the owner of the share). The example uses the production image; use the
staging image name on staging.

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
          # production image; on staging use qbtstagingcontainergrip
          image: qbtcontainers.azurecr.io/qbtcontainergrip:latest
          imagePullPolicy: Always   # the tag is :latest, see section 1
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

Then confirm Chromium kept the save and upload dialog seeds (about 30 seconds after the pod starts):

```bash
kubectl exec <pod> -- sh -c 'tr "," "\n" < /config/chromium/Default/Preferences | grep -A1 file_system_last_picked_directory'
#   expect: an entry naming the Query Builder origin and <DIR>
#   ends in {} => the image is older than v5 (seed discarded)

kubectl exec <pod> -- sh -c 'tr "," "\n" < /config/chromium/Default/Preferences | grep selectfile'
#   expect: "selectfile":{"last_directory":"<DIR>"}
#   nothing printed => the image is older than v6 (uploads open at /config)
```

In the browser session:

- The bookmark bar shows **`Query Builder v6`** (or `... v6 (staging)`).
  Any older label (v5 or below) means an old image is running.
- `chrome://policy`: `DownloadDirectory` and `DefaultDownloadDirectory` both
  show `<DIR>`, with no "Superseding" status.
- Run a query, click **Download Results**, and confirm the save dialog opens
  at the shared drive. Then confirm the file is on the share.
- Click an upload button ("Choose file") and confirm that dialog also opens at
  the shared drive, showing the files on it.

## If it still lands in the wrong place

Send the maintainers the output of the three commands above, plus a
screenshot of `chrome://policy` and the Deployment YAML.
