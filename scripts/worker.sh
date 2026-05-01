#!/bin/bash
# Background job processor for meal analysis queue.
# Processes all pending jobs in data/queue/, oldest first.
# Called by launchd when new files appear in the queue directory.
#
# Uses a lock file to prevent concurrent processing.
#
# Usage:
#   ./scripts/worker.sh          # Process all queued jobs
#   ./scripts/worker.sh --once   # Process one job and exit

set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"
# Set locale for cron (LANG is unset in cron environment)
export LANG="${LANG:-en_US.UTF-8}"

FOOD_LOG_DIR="$(cd "$(dirname "$0")/.." && pwd)"
QUEUE_DIR="$FOOD_LOG_DIR/data/queue"
PROCESSING_DIR="$QUEUE_DIR/processing"
DONE_DIR="$QUEUE_DIR/done"
FAILED_DIR="$QUEUE_DIR/failed"
LOCK_FILE="$QUEUE_DIR/.worker.lock"

DEBUG_LOG="$FOOD_LOG_DIR/data/debug.log"
debug() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [worker] $*" >> "$DEBUG_LOG"; }

mkdir -p "$PROCESSING_DIR" "$DONE_DIR" "$FAILED_DIR"

# --- Lock mechanism ---
acquire_lock() {
  if [ -f "$LOCK_FILE" ]; then
    LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
      debug "worker already running (PID $LOCK_PID), exiting"
      exit 0
    fi
    # Stale lock — remove it
    debug "removing stale lock (PID $LOCK_PID)"
    rm -f "$LOCK_FILE"
  fi
  echo $$ > "$LOCK_FILE"
}

release_lock() {
  rm -f "$LOCK_FILE"
}
trap release_lock EXIT

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

ONCE_MODE=false
[ "${1:-}" = "--once" ] && ONCE_MODE=true

process_job() {
  local job_file="$1"
  local ticket_id
  ticket_id=$(python3 -c "import json; print(json.load(open('$job_file'))['ticket_id'])")
  local basename="${ticket_id}.json"

  debug "processing job: $ticket_id"

  # Move to processing
  mv "$job_file" "$PROCESSING_DIR/$basename"

  # Extract args from job file
  local args_str
  args_str=$(python3 -c "
import json, shlex
job = json.load(open('$PROCESSING_DIR/$basename'))
print(' '.join(shlex.quote(a) for a in job['args']))
")

  # Retry logic for transient failures (e.g. "Auto mode is unavailable for your plan")
  local max_retries=5
  local retry_delay=300
  local attempt=0
  local start_time
  start_time=$(date +%s)
  local output=""
  local exit_code=0

  while [ $attempt -lt $max_retries ]; do
    attempt=$((attempt + 1))
    debug "running: analyze.sh $args_str (attempt $attempt/$max_retries)"

    output=""
    exit_code=0
    output=$(eval "$FOOD_LOG_DIR/scripts/analyze.sh $args_str" 2>>"$DEBUG_LOG") || exit_code=$?

    if [ $exit_code -eq 0 ] && [ -n "$output" ]; then
      break
    fi

    if [ $attempt -lt $max_retries ]; then
      debug "job $ticket_id failed (attempt $attempt/$max_retries, exit=$exit_code), retrying in ${retry_delay}s..."
      sleep $retry_delay
    fi
  done

  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))
  local completed_at
  completed_at=$(date +%Y-%m-%dT%H:%M:%S+09:00)

  # Save output to temp file to avoid shell interpolation issues with base64
  local tmp_output="/tmp/food-log-worker-output-${ticket_id}.txt"

  if [ $exit_code -eq 0 ] && [ -n "$output" ]; then
    debug "job $ticket_id completed in ${duration}s"

    echo -n "$output" > "$tmp_output"
    python3 -c "
import json, sys

job = json.load(open(sys.argv[1]))
job['status'] = 'done'
job['completed_at'] = sys.argv[3]
job['duration_s'] = int(sys.argv[4])
with open(sys.argv[5]) as f:
    job['result_base64'] = f.read()
with open(sys.argv[2], 'w') as f:
    json.dump(job, f, ensure_ascii=False, indent=2)
" "$PROCESSING_DIR/$basename" "$DONE_DIR/$basename" "$completed_at" "$duration" "$tmp_output"

    rm -f "$PROCESSING_DIR/$basename" "$tmp_output"
  else
    debug "job $ticket_id FAILED (exit=$exit_code, duration=${duration}s)"

    python3 -c "
import json, sys

job = json.load(open(sys.argv[1]))
job['status'] = 'failed'
job['failed_at'] = sys.argv[3]
job['duration_s'] = int(sys.argv[4])
job['exit_code'] = int(sys.argv[5])
with open(sys.argv[2], 'w') as f:
    json.dump(job, f, ensure_ascii=False, indent=2)
" "$PROCESSING_DIR/$basename" "$FAILED_DIR/$basename" "$completed_at" "$duration" "$exit_code"

    rm -f "$PROCESSING_DIR/$basename" "$tmp_output"
    rm -f "$QUEUE_DIR/files/${ticket_id}".*
  fi
}

# Process all queued jobs, oldest first
while true; do
  # Find oldest job file in queue (excluding subdirectories)
  job_file=$(find "$QUEUE_DIR" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null \
    | tail -1 || true)

  if [ -z "$job_file" ]; then
    debug "queue empty, exiting"
    break
  fi

  process_job "$job_file"

  if [ "$ONCE_MODE" = true ]; then
    debug "once mode, exiting after one job"
    break
  fi
done

debug "=== WORKER END ==="
