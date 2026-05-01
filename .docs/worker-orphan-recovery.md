# Worker Orphan Recovery — Postmortem & Fix

**Date:** 2026-04-11
**Scope:** `scripts/worker.sh`
**Severity:** Silent data stall — two morning breakfast jobs sat in `data/queue/processing/` for ~1.5 hours with no error, no retry, no alert.

## Symptom

Two jobs submitted from iPhone at 07:27 on 2026-04-11 (`2026-04-10_203500` ひき肉とペンネ, `2026-04-10_204100` お芋とちくわと新玉ねぎツナ) never produced results. They were found stuck in `data/queue/processing/` while the worker cron tick kept logging `queue empty, exiting` every minute.

## Timeline from debug.log

```
07:27:12  submit   job1 (203500) queued
07:27:58  submit   job2 (204100) queued
07:28:00  worker   PID 99406 starts, moves 203500 → processing/, calls claude
07:29:00  worker   next cron tick sees PID 99406 alive → exits cleanly
07:29:??  worker   PID 99406 killed externally (no completion/failure log)
07:30:00  worker   new PID treats stale lock, moves 204100 → processing/, calls claude
07:31:01  worker   next cron tick sees new PID alive → exits cleanly
07:31:??  worker   new PID killed externally
07:32:00+ worker   queue/ root empty → "queue empty" logged every minute forever
```

Neither worker wrote a completion log, a failure log, nor any exit message. The EXIT trap did not run (lock file was left behind, which is why the next worker saw it as stale via `kill -0` probe). That points to **SIGKILL**, not SIGTERM.

## Root Cause

Two layers:

### Proximate cause — macOS sleep / power management
Both worker processes were SIGKILL'd mid-analysis. The strongest suspect is macOS putting the system to sleep while `claude -p --model opus` was running an image OCR pass (45–120s on Opus). Cron-launched long-running processes are vulnerable to PowerManagement termination without warning, and SIGKILL does not run bash EXIT traps.

### Real cause — design flaw in worker.sh
The original worker had no recovery path for jobs left in `processing/`:

1. The main loop uses `find "$QUEUE_DIR" -maxdepth 1` — it only scans queue root, never `processing/`.
2. The EXIT trap only releases the lock; it does not roll the in-flight file back to queue/.
3. No reaper sweeps `processing/` for stale files.

As a result, any worker killed with SIGKILL mid-job orphans its job file forever. The cron-based retry loop is helpless because subsequent workers correctly see an empty queue.

## Fix

Added an orphan-recovery block in `scripts/worker.sh`, placed immediately after `acquire_lock` and before the main processing loop:

```bash
acquire_lock
debug "=== WORKER START ==="

# --- Recover orphaned jobs ---
# Because we now hold the lock, no other worker is processing. Any file left in
# processing/ is from a previous worker that was killed mid-job (e.g. SIGKILL
# from macOS sleep / power management). Move them back to queue/ so the main
# loop below picks them up and retries.
while IFS= read -r orphan; do
  [ -z "$orphan" ] && continue
  orphan_name=$(basename "$orphan")
  debug "recovering orphaned job: $orphan_name"
  mv "$orphan" "$QUEUE_DIR/$orphan_name"
done < <(find "$PROCESSING_DIR" -maxdepth 1 -name '*.json' -type f 2>/dev/null)
```

### Why this is safe

- `acquire_lock` guarantees no other worker is live (stale locks are cleaned via `kill -0`). Every file in `processing/` at this moment is therefore provably abandoned — no race with a running peer.
- The job move is a single-rename within the same filesystem, so it is atomic.
- Re-processing is idempotent:
  - `analyze.sh` writes its pending JSON once, after Claude finishes — no partial files to corrupt.
  - The worker's 5× retry loop treats the recovered job identically to a fresh submission.
  - If recovery-then-retry still fails, the normal `failed/` flow catches it.

### Recovery sequence (future incidents)

1. Claude analysis running when Mac goes to sleep → worker SIGKILL'd → `processing/XXX.json` + stale lock file remain.
2. Mac wakes; within 60s the next cron tick fires worker.sh.
3. Stale lock is cleaned, fresh lock acquired.
4. **New block** sweeps `processing/` → `XXX.json` is moved back to `queue/`.
5. Main loop finds `XXX.json`, re-runs `analyze.sh`, completes normally to `done/`.

No human intervention needed.

## Side Findings (not fixed in this patch)

Noted for future work, deliberately out of scope for this surgical fix:

- **`launchd` agent not installed.** `com.foodlog.worker.plist` uses `WatchPaths` for event-driven processing, but it is not loaded in `~/Library/LaunchAgents/`. The system is running on a cron fallback (`* * * * *`). Event-driven launchd would be more responsive (and potentially less sleep-sensitive if it is configured to wake the Mac on file-add).
- **Spurious `"echo", "ok"` trailing args.** Every submitted job in `data/queue/done/` and `data/queue/failed/` has `"echo", "ok"` appended to `args`. Likely an iOS Shortcut / SSH command-line quoting artifact. Currently harmless because `analyze.sh` ignores unknown trailing positional args, but worth tracing to its source.
- **iCloud vs local pending path.** The architecture doc describes results flowing through `iCloud/FoodLog/pending/`, but the worker actually writes to local `data/pending/`. The base64 round-trip via `job-status.sh --result` makes this fine for the async flow, but the architecture doc is stale on this point.

## Verification

Recovery block was unit-tested in isolation with a synthetic orphan file — the block correctly moved the file from `processing/` back to `queue/` root. Syntactic check with `bash -n` passed. Not yet verified end-to-end in production (would require deliberately killing a running worker).
