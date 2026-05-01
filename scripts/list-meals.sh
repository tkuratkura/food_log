#!/bin/bash
# List meal logs with their IDs, descriptions, and calorie totals.
# Useful for finding a meal_id to pass to save-template.sh.
#
# Usage:
#   ./scripts/list-meals.sh              # List all meals (newest first)
#   ./scripts/list-meals.sh -n 10        # Show last 10 meals
#   ./scripts/list-meals.sh -s ラーメン  # Search by description or item name
#   ./scripts/list-meals.sh -d 2026-03-09  # Filter by date

set -euo pipefail

# Ensure Python can output UTF-8 in non-interactive SSH sessions
export PYTHONIOENCODING=utf-8

FOOD_LOG_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MEALS_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/FoodLog/results"

LIMIT=0
SEARCH=""
DATE_FILTER=""
FORMAT="table"

usage() {
  echo "Usage: $0 [-n COUNT] [-s SEARCH] [-d DATE] [json]" >&2
  echo "" >&2
  echo "Options:" >&2
  echo "  -n COUNT   Show only the last COUNT meals (default: all)" >&2
  echo "  -s SEARCH  Filter by description or food item name" >&2
  echo "  -d DATE    Filter by date (e.g. 2026-03-09)" >&2
  echo "  json     Output as JSON array (for iOS Shortcut)" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  $0                    # List all meals" >&2
  echo "  $0 -n 5               # Last 5 meals" >&2
  echo "  $0 -s ラーメン        # Search for ramen meals" >&2
  echo "  $0 -d 2026-03-10      # Meals on March 10" >&2
  echo "  $0 json -n 20       # Last 20 meals as JSON" >&2
  exit 1
}

# Extract json before getopts (which doesn't handle long options)
args=()
for arg in "$@"; do
  if [ "$arg" = "json" ]; then
    FORMAT="json"
  else
    args+=("$arg")
  fi
done
set -- "${args[@]+"${args[@]}"}"

while getopts "n:s:d:h" opt; do
  case $opt in
    n) LIMIT="$OPTARG" ;;
    s) SEARCH="$OPTARG" ;;
    d) DATE_FILTER="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

if [ ! -d "$MEALS_DIR" ]; then
  echo "No meals directory found: $MEALS_DIR" >&2
  exit 1
fi

python3 -c "
import json, sys, os, glob

meals_dir = sys.argv[1]
limit = int(sys.argv[2])
search = sys.argv[3].lower()
date_filter = sys.argv[4]
fmt = sys.argv[5]

files = sorted(glob.glob(os.path.join(meals_dir, '*.json')), reverse=True)

if date_filter:
    files = [f for f in files if date_filter in os.path.basename(f)]

results = []
for f in files:
    try:
        with open(f) as fh:
            meal = json.load(fh)
        meal_id = meal.get('meal_id', os.path.basename(f).replace('.json', ''))
        desc = meal.get('meal_description', '')
        calories = meal.get('totals', {}).get('calories', 0)
        protein = meal.get('totals', {}).get('protein_g', 0)
        fat = meal.get('totals', {}).get('fat_g', 0)
        carbs = meal.get('totals', {}).get('carbs_g', 0)
        items = [item.get('name', '') for item in meal.get('food_items', [])]
        items_str = ', '.join(items)
        timestamp = meal.get('timestamp', '')

        if search:
            haystack = (desc + ' ' + items_str).lower()
            if search not in haystack:
                continue

        results.append({
            'meal_id': meal_id, 'calories': calories,
            'protein_g': protein, 'fat_g': fat, 'carbs_g': carbs,
            'description': desc, 'items': items_str, 'timestamp': timestamp,
        })
    except (json.JSONDecodeError, KeyError):
        continue

if limit > 0:
    results = results[:limit]

if fmt == 'json':
    if not results:
        print('[]')
    else:
        print(json.dumps(results, ensure_ascii=False))
    sys.exit(0)

if not results:
    print('No meals found.', file=sys.stderr)
    sys.exit(0)

id_w = max(len(r['meal_id']) for r in results)
cal_w = max(len(str(r['calories'])) for r in results)

print(f'{\"ID\":<{id_w}}  {\"kcal\":>{cal_w}}  Description')
print(f'{\"-\" * id_w}  {\"-\" * cal_w}  {\"-\" * 40}')
for r in results:
    line = r['description'] if r['description'] else r['items']
    if len(line) > 60:
        line = line[:57] + '...'
    print(f'{r[\"meal_id\"]:<{id_w}}  {r[\"calories\"]:>{cal_w}}  {line}')

print(f'\nTotal: {len(results)} meals')
" "$MEALS_DIR" "$LIMIT" "$SEARCH" "$DATE_FILTER" "$FORMAT"
