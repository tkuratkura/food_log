#!/bin/bash
# Delete meal result files from iCloud Drive.
# Designed to be called from iOS Shortcut via SSH.
#
# Usage:
#   ./scripts/delete-meal.sh <meal_id>                  # Delete one meal
#   ./scripts/delete-meal.sh <meal_id1> <meal_id2> ...  # Delete multiple meals
#   ./scripts/delete-meal.sh --date 2026-04-06          # Delete all meals for a date
#   ./scripts/delete-meal.sh --preset 平日昼間           # Delete today's preset meals
#   ./scripts/delete-meal.sh --preset 平日昼間 --date 2026-04-05  # Delete preset for a date

set -euo pipefail

export PYTHONIOENCODING=utf-8

FOOD_LOG_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MEALS_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/FoodLog/results"
PRESETS_DIR="$FOOD_LOG_DIR/data/presets"

DEBUG_LOG="$FOOD_LOG_DIR/data/debug.log"
debug() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [delete-meal] $*" >> "$DEBUG_LOG"; }
debug "=== CALL === argv=[$*] ppid=$PPID pwd=$(pwd)"

show_help() {
  echo "Usage: $0 <meal_id> [meal_id2 ...]"
  echo "       $0 --date <YYYY-MM-DD>"
  echo "       $0 --preset <preset_name> [--date <YYYY-MM-DD>]"
  echo ""
  echo "Delete meal result files from iCloud Drive."
  echo ""
  echo "Options:"
  echo "  --date <YYYY-MM-DD>     Delete all meals for a specific date"
  echo "  --preset <preset_name>  Delete meals matching a preset's time slots"
}

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  show_help
  exit 0
fi

# Parse arguments
DATE_FILTER=""
PRESET_NAME=""
MEAL_IDS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --date)
      DATE_FILTER="$2"
      shift 2
      ;;
    --preset)
      PRESET_NAME="$2"
      shift 2
      ;;
    *)
      MEAL_IDS+=("$1")
      shift
      ;;
  esac
done

deleted=0
DELETED_TIMESTAMPS=()

delete_file() {
  local meal_id="$1"
  local file="$MEALS_DIR/${meal_id}.json"
  if [ -f "$file" ]; then
    # Read timestamp before deleting
    local ts
    ts=$(python3 -c "import json; print(json.load(open('$file')).get('timestamp',''))" 2>/dev/null || true)
    rm -f "$file"
    DELETED_TIMESTAMPS+=("$ts")
    deleted=$((deleted + 1))
  fi
}

if [ -n "$PRESET_NAME" ]; then
  # Delete meals matching a preset's time slots for a given date
  PRESET_FILE="$PRESETS_DIR/${PRESET_NAME}.json"
  if [ ! -f "$PRESET_FILE" ]; then
    echo "Error: preset '$PRESET_NAME' not found" >&2
    exit 1
  fi
  [ -z "$DATE_FILTER" ] && DATE_FILTER="$(date +%Y-%m-%d)"
  debug "delete preset=$PRESET_NAME date=$DATE_FILTER"

  python3 -c "
import json, sys, os

preset_file = sys.argv[1]
date_str = sys.argv[2]
meals_dir = sys.argv[3]

with open(preset_file) as f:
    preset = json.load(f)

time_counter = {}
timestamps = []

for entry in preset['meals']:
    time_str = entry['time']
    offset = time_counter.get(time_str, 0)
    time_counter[time_str] = offset + 1
    hh, mm = time_str.split(':')
    meal_id = f'{date_str}_{hh}{mm}{offset:02d}'
    fpath = os.path.join(meals_dir, f'{meal_id}.json')
    if os.path.exists(fpath):
        with open(fpath) as f:
            ts = json.load(f).get('timestamp', '')
        os.remove(fpath)
        timestamps.append(ts)

print(json.dumps(timestamps))
print(f'Deleted {len(timestamps)} meals', file=sys.stderr)
" "$PRESET_FILE" "$DATE_FILTER" "$MEALS_DIR"
  exit 0

elif [ -n "$DATE_FILTER" ]; then
  # Delete all meals for a date
  debug "delete date=$DATE_FILTER"
  for f in "$MEALS_DIR"/${DATE_FILTER}*.json; do
    [ -f "$f" ] || continue
    meal_id="$(basename "$f" .json)"
    delete_file "$meal_id"
  done

else
  # Delete specific meal IDs
  debug "delete ids=${MEAL_IDS[*]}"
  for meal_id in "${MEAL_IDS[@]}"; do
    delete_file "$meal_id"
  done
fi

# Output deleted timestamps as JSON array for iOS Shortcut HealthKit cleanup
python3 -c "
import json, sys
timestamps = sys.argv[1:]
print(json.dumps(timestamps))
" "${DELETED_TIMESTAMPS[@]+"${DELETED_TIMESTAMPS[@]}"}"
echo "Deleted $deleted meals" >&2
