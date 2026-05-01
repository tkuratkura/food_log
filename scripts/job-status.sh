#!/bin/bash
# Check the status of a submitted meal analysis job.
#
# Usage:
#   ./scripts/job-status.sh <ticket_id>          # Check status
#   ./scripts/job-status.sh <ticket_id> --result  # If done, output base64 result
#   ./scripts/job-status.sh --list                # List all jobs
#
# Output:
#   {"ticket_id":"...","status":"queued|processing|done|failed"}
#   With --result and status=done: outputs the base64-encoded meal JSON

set -euo pipefail

FOOD_LOG_DIR="$(cd "$(dirname "$0")/.." && pwd)"
QUEUE_DIR="$FOOD_LOG_DIR/data/queue"

# --- List mode ---
if [ "${1:-}" = "--list" ]; then
  python3 -c "
import json, os, glob

queue_dir = '$QUEUE_DIR'
jobs = []

for status, subdir in [('queued', ''), ('processing', 'processing'), ('done', 'done'), ('failed', 'failed')]:
    search_dir = os.path.join(queue_dir, subdir) if subdir else queue_dir
    for f in glob.glob(os.path.join(search_dir, '*.json')):
        try:
            with open(f) as fh:
                job = json.load(fh)
            jobs.append({
                'ticket_id': job.get('ticket_id', os.path.basename(f)),
                'status': status,
                'submitted_at': job.get('submitted_at', ''),
            })
        except:
            pass

jobs.sort(key=lambda x: x.get('submitted_at', ''), reverse=True)
print(json.dumps(jobs, ensure_ascii=False, indent=2))
"
  exit 0
fi

# --- Status check for specific ticket ---
if [ $# -lt 1 ]; then
  echo '{"error":"Usage: job-status.sh <ticket_id> [--result]"}' >&2
  exit 1
fi

TICKET_ID="$1"
WANT_RESULT=false
[ "${2:-}" = "--result" ] && WANT_RESULT=true

BASENAME="${TICKET_ID}.json"

# Check each status directory
if [ -f "$QUEUE_DIR/$BASENAME" ]; then
  echo "{\"ticket_id\":\"$TICKET_ID\",\"status\":\"queued\"}"
elif [ -f "$QUEUE_DIR/processing/$BASENAME" ]; then
  echo "{\"ticket_id\":\"$TICKET_ID\",\"status\":\"processing\"}"
elif [ -f "$QUEUE_DIR/done/$BASENAME" ]; then
  if [ "$WANT_RESULT" = true ]; then
    # Output just the base64 result (same format as analyze.sh)
    python3 -c "
import json
job = json.load(open('$QUEUE_DIR/done/$BASENAME'))
print(job.get('result_base64', ''))
"
  else
    python3 -c "
import json
job = json.load(open('$QUEUE_DIR/done/$BASENAME'))
print(json.dumps({
    'ticket_id': job['ticket_id'],
    'status': 'done',
    'completed_at': job.get('completed_at', ''),
    'duration_s': job.get('duration_s', 0),
}, ensure_ascii=False))
"
  fi
elif [ -f "$QUEUE_DIR/failed/$BASENAME" ]; then
  python3 -c "
import json
job = json.load(open('$QUEUE_DIR/failed/$BASENAME'))
print(json.dumps({
    'ticket_id': job['ticket_id'],
    'status': 'failed',
    'failed_at': job.get('failed_at', ''),
    'exit_code': job.get('exit_code', 1),
}, ensure_ascii=False))
"
else
  # Not in queue — check if result already exists in pending/results
  ICLOUD_BASE="$HOME/Library/Mobile Documents/com~apple~CloudDocs/FoodLog"
  if [ -f "$FOOD_LOG_DIR/data/pending/$BASENAME" ] || [ -f "$ICLOUD_BASE/results/$BASENAME" ]; then
    echo "{\"ticket_id\":\"$TICKET_ID\",\"status\":\"done\"}"
  else
    echo "{\"ticket_id\":\"$TICKET_ID\",\"status\":\"not_found\"}"
  fi
fi
