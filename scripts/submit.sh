#!/bin/bash
# Submit a meal analysis job to the background queue.
# Returns a ticket ID immediately — actual processing happens via worker.sh.
#
# For templates/presets, runs synchronously (already instant).
# For image/text analysis (slow Claude call), queues the job and exits.
#
# Usage:
#   ./scripts/submit.sh /path/to/photo.jpg                    # Queue image analysis
#   ./scripts/submit.sh /path/to/photo.jpg "100ml小鉢"         # Queue image + notes
#   ./scripts/submit.sh "味噌ラーメンと餃子5個"                   # Queue text analysis
#   ./scripts/submit.sh @炒り大豆おやつ                          # Template (instant, no queue)
#   ./scripts/submit.sh --time "2026-03-16_120000" "カレー"     # Queue with custom time
#
# Output (queued jobs):
#   {"ticket_id":"2026-04-09_123000","status":"queued"}
#
# Output (templates/presets):
#   Same as analyze.sh (base64-encoded JSON)

set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

FOOD_LOG_DIR="$(cd "$(dirname "$0")/.." && pwd)"
QUEUE_DIR="$FOOD_LOG_DIR/data/queue"

DEBUG_LOG="$FOOD_LOG_DIR/data/debug.log"
debug() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [submit] $*" >> "$DEBUG_LOG"; }
debug "=== SUBMIT === argc=$# pwd=$(pwd) shell=$SHELL tty=$(tty 2>/dev/null || echo none)"
for _i in "$@"; do
  debug "  arg: [$_i]"
done

TEMPLATES_DIR="$FOOD_LOG_DIR/data/templates"
PRESETS_DIR="$FOOD_LOG_DIR/data/presets"

# --- Check if input is a template or preset (fast path) ---
ORIGINAL_ARGS=("$@")
CUSTOM_TIME=""
check_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --time) CUSTOM_TIME="$2"; shift 2 ;;
    *) check_args+=("$1"); shift ;;
  esac
done
set -- "${check_args[@]+"${check_args[@]}"}"

if [ $# -ge 1 ]; then
  STRIPPED="$(echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^[@＠]//')"

  if [ -f "$TEMPLATES_DIR/${STRIPPED}.json" ]; then
    debug "template detected — running analyze.sh directly"
    exec "$FOOD_LOG_DIR/scripts/analyze.sh" "${ORIGINAL_ARGS[@]}"
  fi

  if [ -f "$PRESETS_DIR/${STRIPPED}.json" ]; then
    debug "preset detected — running analyze.sh directly"
    exec "$FOOD_LOG_DIR/scripts/analyze.sh" "${ORIGINAL_ARGS[@]}"
  fi
fi

# --- Slow path: write job file and return immediately ---
mkdir -p "$QUEUE_DIR"

if [ -n "$CUSTOM_TIME" ]; then
  TICKET_ID="$CUSTOM_TIME"
else
  TICKET_ID=$(date +%Y-%m-%d_%H%M%S)
fi

# Ensure unique ticket ID (avoid collision when multiple jobs share the same --time)
while [ -f "$QUEUE_DIR/${TICKET_ID}.json" ] || \
      [ -f "$QUEUE_DIR/processing/${TICKET_ID}.json" ]; do
  PREFIX="${TICKET_ID%??}"
  SECS="${TICKET_ID: -2}"
  SECS=$(( 10#$SECS + 1 ))
  TICKET_ID=$(printf "%s%02d" "$PREFIX" "$SECS")
  debug "ticket ID collision, incremented to $TICKET_ID"
done

# Update --time in ORIGINAL_ARGS so analyze.sh uses the deduplicated ticket ID
if [ -n "$CUSTOM_TIME" ] && [ "$TICKET_ID" != "$CUSTOM_TIME" ]; then
  NEW_ARGS=()
  for i in "${!ORIGINAL_ARGS[@]}"; do
    if [ "${ORIGINAL_ARGS[$i]}" = "$CUSTOM_TIME" ] && [ $i -gt 0 ] && [ "${ORIGINAL_ARGS[$((i-1))]}" = "--time" ]; then
      NEW_ARGS+=("$TICKET_ID")
    else
      NEW_ARGS+=("${ORIGINAL_ARGS[$i]}")
    fi
  done
  ORIGINAL_ARGS=("${NEW_ARGS[@]}")
fi

ISO_NOW=$(date +%Y-%m-%dT%H:%M:%S+09:00)
JOB_FILE="$QUEUE_DIR/${TICKET_ID}.json"

python3 -c "
import json, sys
job = {
    'ticket_id': sys.argv[1],
    'submitted_at': sys.argv[2],
    'args': sys.argv[4:],
    'status': 'queued'
}
with open(sys.argv[3], 'w') as f:
    json.dump(job, f, ensure_ascii=False, indent=2)
" "$TICKET_ID" "$ISO_NOW" "$JOB_FILE" "${ORIGINAL_ARGS[@]}"

debug "queued job: $JOB_FILE (ticket=$TICKET_ID, stored_argc=${#ORIGINAL_ARGS[@]})"
for _i in "${ORIGINAL_ARGS[@]}"; do
  debug "  stored arg: [$_i]"
done
echo "{\"ticket_id\":\"${TICKET_ID}\",\"status\":\"queued\"}"
