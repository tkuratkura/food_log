#!/bin/bash
# List pending (unconfirmed) meal analyses.
#
# Usage:
#   ./scripts/list-pending.sh              # Human-readable table
#   ./scripts/list-pending.sh --names      # One line per meal for iOS Shortcut
#   ./scripts/list-pending.sh --base64     # base64-encoded JSON (like analyze.sh)

set -euo pipefail

export PYTHONIOENCODING=utf-8

FOOD_LOG_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PENDING_DIR="$FOOD_LOG_DIR/data/pending"
TMPFILE="/tmp/food-log-pending-list.json"

FORMAT="${1:-table}"

if [ ! -d "$PENDING_DIR" ] || [ -z "$(ls -A "$PENDING_DIR" 2>/dev/null)" ]; then
  case "$FORMAT" in
    --base64)
      echo -n '{"count":0,"meals":[]}' > "$TMPFILE"
      base64 < "$TMPFILE"
      ;;
    --names)
      ;;
    *)
      echo "No pending meals." >&2
      ;;
  esac
  exit 0
fi

case "$FORMAT" in
  --base64)
    python3 -c "
import json, sys, os, glob

pending_dir = sys.argv[1]
outfile = sys.argv[2]

files = sorted(glob.glob(os.path.join(pending_dir, '*.json')), reverse=True)

results = []
for f in files:
    try:
        with open(f) as fh:
            meal = json.load(fh)
        meal_id = meal.get('meal_id', os.path.basename(f).replace('.json', ''))
        desc = meal.get('meal_description', '')
        cal = meal.get('totals', {}).get('calories', 0)
        protein = meal.get('totals', {}).get('protein_g', 0)
        fat = meal.get('totals', {}).get('fat_g', 0)
        carbs = meal.get('totals', {}).get('carbs_g', 0)
        fiber = meal.get('totals', {}).get('fiber_g', 0)
        timestamp = meal.get('timestamp', '')
        results.append({
            'meal_id': meal_id, 'description': desc, 'calories': cal,
            'protein_g': protein, 'fat_g': fat, 'carbs_g': carbs,
            'fiber_g': fiber, 'timestamp': timestamp,
        })
    except (json.JSONDecodeError, KeyError):
        continue

with open(outfile, 'w', encoding='utf-8') as f:
    json.dump({'count': len(results), 'meals': results}, f, ensure_ascii=False)
" "$PENDING_DIR" "$TMPFILE"
    base64 < "$TMPFILE"
    ;;
  --names)
    python3 -c "
import json, sys, os, glob

pending_dir = sys.argv[1]
for f in sorted(glob.glob(os.path.join(pending_dir, '*.json')), reverse=True):
    try:
        with open(f) as fh:
            meal = json.load(fh)
        meal_id = meal.get('meal_id', os.path.basename(f).replace('.json', ''))
        desc = meal.get('meal_description', '')
        cal = meal.get('totals', {}).get('calories', 0)
        print(f'{desc} ({cal}kcal)\t{meal_id}')
    except (json.JSONDecodeError, KeyError):
        continue
" "$PENDING_DIR"
    ;;
  *)
    python3 -c "
import json, sys, os, glob

pending_dir = sys.argv[1]
results = []
for f in sorted(glob.glob(os.path.join(pending_dir, '*.json')), reverse=True):
    try:
        with open(f) as fh:
            meal = json.load(fh)
        meal_id = meal.get('meal_id', os.path.basename(f).replace('.json', ''))
        desc = meal.get('meal_description', '')
        cal = meal.get('totals', {}).get('calories', 0)
        results.append((meal_id, cal, desc))
    except (json.JSONDecodeError, KeyError):
        continue

if not results:
    print('No pending meals.', file=sys.stderr)
    sys.exit(0)

for meal_id, cal, desc in results:
    print(f'  {meal_id}  {cal:>4} kcal  {desc}')

print(f'\nTotal: {len(results)} pending')
" "$PENDING_DIR"
    ;;
esac
