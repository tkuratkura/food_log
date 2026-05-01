#!/bin/bash
# Process all pending meals: output base64 for HealthKit logging and move to results.
#
# Each pending meal is output as one base64 line (full JSON with all 39 nutrients),
# then automatically confirmed (moved to iCloud results/).
#
# Usage:
#   ./scripts/process-pending.sh          # Process all pending meals
#   ./scripts/process-pending.sh --dry    # Output base64 without confirming
#
# Output: one base64-encoded JSON line per meal (same format as analyze.sh)
#         iOS Shortcut splits by newline and processes each line.
# If no pending meals exist, outputs nothing and exits 0.

set -euo pipefail

FOOD_LOG_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PENDING_DIR="$FOOD_LOG_DIR/data/pending"

ICLOUD_BASE="$HOME/Library/Mobile Documents/com~apple~CloudDocs/FoodLog"
RESULTS_DIR="$ICLOUD_BASE/results"

DRY_RUN=false
[ "${1:-}" = "--dry" ] && DRY_RUN=true

if [ ! -d "$PENDING_DIR" ] || [ -z "$(ls -A "$PENDING_DIR" 2>/dev/null)" ]; then
  exit 0
fi

mkdir -p "$RESULTS_DIR"

for f in "$PENDING_DIR"/*.json; do
  [ -f "$f" ] || continue
  base64 < "$f"
  if [ "$DRY_RUN" = false ]; then
    mv "$f" "$RESULTS_DIR/$(basename "$f")"
  fi
done
