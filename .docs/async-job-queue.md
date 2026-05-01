# Async Job Queue System

## Overview

The async job queue decouples meal submission from analysis processing. When a user submits a meal via SSH from iPhone, the script returns a ticket ID immediately instead of waiting for Claude analysis to complete. A background worker (managed by launchd) picks up queued jobs and processes them.

## Architecture

```
iPhone (SSH) → submit.sh → data/queue/TICKET.json → [exit immediately]
                                    ↓
             launchd (WatchPaths) → worker.sh → analyze.sh → pending/*.json
                                    ↓
                             data/queue/done/TICKET.json (with base64 result)
```

## Components

### `scripts/submit.sh`
- **Fast path**: Templates and presets are passed directly to `analyze.sh` (already instant)
- **Slow path**: Image/text analysis writes a job file to `data/queue/` and returns `{"ticket_id":"...","status":"queued"}`
- Same argument interface as `analyze.sh` (`--time`, image paths, text, `@template`)

### `scripts/worker.sh`
- Triggered by launchd when files appear in `data/queue/`
- Processes all pending jobs sequentially (oldest first)
- Uses a lock file to prevent concurrent processing
- Moves jobs through: `queue/ → processing/ → done/` (or `failed/`)
- Stores base64 result in done record for later retrieval

### `scripts/job-status.sh`
- Check individual job: `job-status.sh <ticket_id>` → returns JSON status
- Get result: `job-status.sh <ticket_id> --result` → outputs base64 (same as analyze.sh)
- List all: `job-status.sh --list` → JSON array of all jobs

### LaunchAgent (`com.foodlog.worker.plist`)
- Installed at `~/Library/LaunchAgents/com.foodlog.worker.plist`
- Watches `data/queue/` directory for new files
- Runs `worker.sh` automatically when a job is submitted

## Queue Directory Structure

```
data/queue/
├── TICKET_ID.json          # Pending (waiting for worker)
├── processing/
│   └── TICKET_ID.json      # Currently being analyzed
├── done/
│   └── TICKET_ID.json      # Completed (includes result_base64)
└── failed/
    └── TICKET_ID.json      # Failed (includes exit_code)
```

## Job File Format

```json
{
  "ticket_id": "2026-04-09_123000",
  "submitted_at": "2026-04-09T12:30:00+09:00",
  "args": ["--time", "2026-04-09_123000", "/path/to/photo.jpg"],
  "status": "queued"
}
```

After completion, `done/` records add: `completed_at`, `duration_s`, `result_base64`.

## iOS Shortcut Integration

### Submission (replaces current analyze.sh call)
```
SSH: ./scripts/submit.sh --time "2026-04-09_120000" "/path/to/photo.jpg"
Output: {"ticket_id":"2026-04-09_120000","status":"queued"}
```

### Status Check (new, optional)
```
SSH: ./scripts/job-status.sh 2026-04-09_120000
Output: {"ticket_id":"2026-04-09_120000","status":"done","duration_s":45}
```

### Result Retrieval (when done)
```
SSH: ./scripts/job-status.sh 2026-04-09_120000 --result
Output: <base64 encoded meal JSON, same format as analyze.sh>
```

### Templates/Presets (unchanged)
Templates and presets still return immediately with base64 — no queue involved.

## LaunchAgent Management

```bash
# Install
cp com.foodlog.worker.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.foodlog.worker.plist

# Uninstall
launchctl unload ~/Library/LaunchAgents/com.foodlog.worker.plist
rm ~/Library/LaunchAgents/com.foodlog.worker.plist

# Check status
launchctl list | grep foodlog
```
