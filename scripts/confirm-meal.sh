#!/bin/bash
# Move a meal from pending to results (confirms the meal for collection).
# Also used to delete a pending meal on cancel.
#
# Usage:
#   ./scripts/confirm-meal.sh <meal_id>          # Move pending → results
#   ./scripts/confirm-meal.sh --delete <meal_id>  # Delete from pending

set -euo pipefail

FOOD_LOG_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PENDING_DIR="$FOOD_LOG_DIR/data/pending"

ICLOUD_BASE="$HOME/Library/Mobile Documents/com~apple~CloudDocs/FoodLog"
RESULTS_DIR="$ICLOUD_BASE/results"

DEBUG_LOG="$FOOD_LOG_DIR/data/debug.log"
debug() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [confirm-meal] $*" >> "$DEBUG_LOG"; }
debug "=== CALL === argv=[$*] ppid=$PPID pwd=$(pwd)"

if [ $# -lt 1 ]; then
  echo "Usage: $0 [--delete] <meal_id>" >&2
  exit 1
fi

DELETE=false
if [ "$1" = "--delete" ]; then
  DELETE=true
  shift
fi

MEAL_ID="$1"
PENDING_FILE="$PENDING_DIR/${MEAL_ID}.json"
RESULTS_FILE="$RESULTS_DIR/${MEAL_ID}.json"

# Already in results (e.g. template/preset) — nothing to move.
# --delete must NOT touch results: templates are confirmed on creation, and
# iOS Shortcut calls `confirm-meal --delete` as a cleanup step expecting a
# pending file to exist. For templates there is no pending, so we silently
# no-op instead of deleting the already-confirmed results file.
if [ ! -f "$PENDING_FILE" ] && [ -f "$RESULTS_FILE" ]; then
  if [ "$DELETE" = true ]; then
    debug "noop --delete: template/preset file in results, not touching: $MEAL_ID"
  else
    debug "noop: already in results, pending absent: $MEAL_ID"
  fi
  exit 0
fi

if [ ! -f "$PENDING_FILE" ]; then
  debug "pending not found: $PENDING_FILE"
  echo "Not found: $PENDING_FILE" >&2
  exit 1
fi

if [ "$DELETE" = true ]; then
  debug "DELETE pending file: $PENDING_FILE"
  rm -f "$PENDING_FILE"
else
  debug "move pending → results: $MEAL_ID"
  mkdir -p "$RESULTS_DIR"
  mv "$PENDING_FILE" "$RESULTS_DIR/${MEAL_ID}.json"
fi
