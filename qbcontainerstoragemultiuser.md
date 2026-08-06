# QB Container — Storage & Multi-User Discussion (Dev Meeting Notes)

## 1. How storage works today

- The container runs **one Chromium browser session**, shown to whoever
  connects through a web VNC viewer (noVNC) on port `4443`.
- Downloads go to a **single folder inside the container**, `/downloads`,
  which is mapped ("mounted") to a real folder on the host machine or a
  network share:
  ```bash
  -v /files/shared/drive:/downloads:rw
  ```
- Everyone who saves a file from that browser session saves it into that
  **same shared folder**. There's no concept of "my folder vs. your folder"
  built in today — it's one shared drop point.

## 2. The core issue: this is a single-session container

This is the part worth being explicit about in the meeting, because it
changes what "multiple users" can even mean here:

> **One container = one desktop, one browser, one keyboard/mouse — not one
> per visitor.**

If two people open the container's URL at the same time, they are **not**
getting two independent sessions. They're looking at, and fighting over,
**the exact same screen** — like two people sharing one remote-desktop
session. Whoever clicks last wins.

So "many users on the same container" today already means "one shared
session, taking turns." That's true *before* we even get to the storage
question.

## 3. Can users get their own download folder?

Two different answers depending on what we mean by "own folder":

### Option A — Self-service subfolders inside the shared drive (works today, no changes needed)

Users can already create their own folder by hand:

- Press `Ctrl+S` (or right-click → "Save Page As") to open the browser's
  native save dialog.
- That dialog has a normal "New Folder" button, like any file save window.
- If they create the folder **inside `/downloads`**, it's real — it lives on
  the shared network drive, survives restarts, and is visible to everyone
  else using that drive.

So a lightweight convention like `/downloads/alice`, `/downloads/bob` works
immediately, with zero engineering — it's just a shared drive with
subfolders people manage themselves.

**Limitation:** this only organizes *files*, it doesn't give separate
*people* separate *sessions* — see point 2 above. It's one desk with labeled
drawers, not separate desks.

**Side note:** that same save dialog can technically browse other folders
inside the container (not just `/downloads`) — a small crack in the
"locked-down kiosk" idea. There's a setting to close that (`policy.json` →
`AllowFileSelectDialogs: false`) if we'd rather remove the dialog entirely
and only allow automatic silent downloads to `/downloads`.

### Option B — Real per-user isolation (needs a design decision)

If we actually want separate people working **at the same time**, each with
their own screen and their own folder, that requires **one container per
user session**, not one shared container:

- Spin up a fresh container per login/session.
- Give each one its own volume mount pointing at that user's own folder,
  e.g. `/files/users/alice/downloads`.
- Put something in front (reverse proxy / session broker) that routes each
  user to their own container and tears it down when they're done.

This is the same pattern used by browser-isolation products like Kasm,
Citrix, or Guacamole — a session-per-container model, not multiple people
sharing one container's screen.

**This is the decision to make as a team:** do we need true concurrent,
isolated sessions (Option B, real engineering effort), or is "one shared
drive with self-managed subfolders" (Option A) good enough for how this is
actually used?

## 4. Recommendation

- **Short term / no extra work:** adopt the subfolder convention
  (`/downloads/<username>`) as a naming standard for the shared drive.
  Optionally lock down the save dialog (`AllowFileSelectDialogs: false`) if
  filesystem browsing is a concern.
- **If concurrent multi-user access becomes a real requirement:** plan for
  Option B — a container-per-session model with a broker/orchestrator in
  front. This is a bigger piece of work (session provisioning, teardown,
  routing) and should be scoped as its own project, not bolted onto the
  current single-container image.

---
*This document summarizes a design discussion — no code changes have been
made yet. Happy to prototype either option once the team decides which
direction to go.*
