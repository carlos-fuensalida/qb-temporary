# QB Container — Usage/Idle Detection via `xprintidle`

Yes, this is exactly the signal to use for usage detection. The moment any
real input happens — mouse move, keypress, click over noVNC — the counter
resets to near-zero. So a simple polling pattern works:

```bash
# returns idle time in ms; treat anything under your threshold as "active"
IDLE_MS=$(docker exec qb sh -c 'DISPLAY=:0 xprintidle')
THRESHOLD_MS=$((15 * 60 * 1000))   # 15 minutes

if [ "$IDLE_MS" -lt "$THRESHOLD_MS" ]; then
  echo "active"
else
  echo "idle for $((IDLE_MS / 60000)) minutes"
fi
```

## Caveats worth knowing before you build automation on it

- **It only reflects input events, not "is Chromium doing something."** A
  page auto-refreshing, or a long-running query in Query Builder itself,
  doesn't count as activity. If your users sometimes kick off a long
  operation and then don't touch the mouse while waiting, a short idle
  threshold could flag them as idle mid-task — so pick a threshold with some
  slack (15–30 min is typical for this kind of session-timeout logic).
- **It resets on *any* input**, including someone just wiggling the mouse to
  keep it "active" without actually using the app — not something you can
  distinguish from real work with this signal alone.
- **It has nothing to do with whether a noVNC client is even connected** — a
  fully disconnected session with a stale idle counter looks identical to a
  connected-but-untouched one. If you need to tell those apart, pair it with
  the `ss -tn` connection check (from earlier) — connected + idle > threshold
  = "connected but abandoned"; not connected at all = "no session."

## Next step

This can be turned into an actual `idle-watch` service under
`root/etc/services.d/` (same pattern as the existing `fix-downloads`
service) that polls this on a loop and writes state somewhere you can act
on — say the word and it can be added to the `Dockerfile`/`root/` tree.
