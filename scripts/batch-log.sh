#!/bin/bash
# Log multiple template meals at once from a preset definition.
# Each meal is saved as an individual JSON in iCloud results, then a combined
# base64-encoded payload is output for iOS Shortcut compatibility.
#
# Usage:
#   ./scripts/batch-log.sh 平日昼間                         # Log preset for today
#   ./scripts/batch-log.sh 平日昼間 2026-04-07              # Log preset for a specific date
#   ./scripts/batch-log.sh --list                           # List available presets
#   ./scripts/batch-log.sh --show 平日昼間                   # Show preset contents

set -euo pipefail

FOOD_LOG_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRESETS_DIR="$FOOD_LOG_DIR/data/presets"
TEMPLATES_DIR="$FOOD_LOG_DIR/data/templates"
ICLOUD_BASE="$HOME/Library/Mobile Documents/com~apple~CloudDocs/FoodLog"
MEALS_DIR="$ICLOUD_BASE/results"

DEBUG_LOG="$FOOD_LOG_DIR/data/debug.log"
debug() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] batch: $*" >> "$DEBUG_LOG"; }

show_help() {
  echo "Usage: $0 <preset_name> [YYYY-MM-DD]"
  echo "       $0 --list"
  echo "       $0 --show <preset_name>"
  echo ""
  echo "Log multiple template meals at once from a preset."
  echo ""
  echo "Options:"
  echo "  --list          List available presets"
  echo "  --show <name>   Show meals in a preset"
  echo "  YYYY-MM-DD      Date to log for (default: today)"
  echo ""
  echo "Available presets:"
  list_presets
}

list_presets() {
  for f in "$PRESETS_DIR"/*.json; do
    [ -f "$f" ] || continue
    local name=$(basename "$f" .json)
    local desc=$(python3 -c "import json; print(json.load(open('$f')).get('description',''))" 2>/dev/null)
    local count=$(python3 -c "import json; print(len(json.load(open('$f')).get('meals',[])))" 2>/dev/null)
    printf "  %-20s %d meals  %s\n" "$name" "$count" "$desc"
  done
}

show_preset() {
  local preset_file="$PRESETS_DIR/${1}.json"
  if [ ! -f "$preset_file" ]; then
    echo "Error: preset '$1' not found" >&2
    exit 1
  fi
  python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    preset = json.load(f)
print(f\"Preset: {preset['preset_name']}\")
print(f\"Description: {preset.get('description', '')}\")
print(f\"Meals ({len(preset['meals'])}):\")
for m in preset['meals']:
    print(f\"  {m['time']}  @{m['template']}\")
" "$preset_file"
}

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  show_help
  exit 0
fi

if [ "$1" = "--list" ]; then
  list_presets
  exit 0
fi

if [ "$1" = "--show" ]; then
  [ $# -lt 2 ] && { echo "Error: --show requires a preset name" >&2; exit 1; }
  show_preset "$2"
  exit 0
fi

# Main: log preset
PRESET_NAME="$1"
PRESET_FILE="$PRESETS_DIR/${PRESET_NAME}.json"
DATE="${2:-$(date +%Y-%m-%d)}"

if [ ! -f "$PRESET_FILE" ]; then
  echo "Error: preset '$PRESET_NAME' not found in $PRESETS_DIR/" >&2
  echo "Available presets:"
  list_presets
  exit 1
fi

debug "=== START batch === preset=$PRESET_NAME date=$DATE"
mkdir -p "$MEALS_DIR"

# Process all meals in the preset
python3 -c "
import json, sys, os
from datetime import datetime

preset_file = sys.argv[1]
templates_dir = sys.argv[2]
meals_dir = sys.argv[3]
date_str = sys.argv[4]

with open(preset_file) as f:
    preset = json.load(f)

logged_meals = []
time_counter = {}  # track duplicate times for unique timestamps

for entry in preset['meals']:
    template_name = entry['template']
    time_str = entry['time']

    # Load template
    tpl_file = os.path.join(templates_dir, f'{template_name}.json')
    if not os.path.exists(tpl_file):
        print(f'WARNING: template \"{template_name}\" not found, skipping', file=sys.stderr)
        continue

    with open(tpl_file) as f:
        template = json.load(f)

    # Generate unique timestamp (offset seconds for duplicate times)
    time_key = time_str
    offset = time_counter.get(time_key, 0)
    time_counter[time_key] = offset + 1

    hh, mm = time_str.split(':')
    ss = offset  # 0, 1, 2... seconds offset for same-time entries
    timestamp = f'{date_str}_{hh}{mm}{ss:02d}'
    iso_timestamp = f'{date_str}T{hh}:{mm}:{ss:02d}+09:00'

    # Create meal JSON
    meal = {
        'meal_id': timestamp,
        'timestamp': iso_timestamp,
        'image_path': None,
        'input_type': 'template',
        'input_text': f'@{template_name}',
        'food_items': template['food_items'],
        'totals': template['totals'],
        'meal_description': template.get('meal_description', '')
    }

    outfile = os.path.join(meals_dir, f'{timestamp}.json')
    with open(outfile, 'w') as f:
        json.dump(meal, f, ensure_ascii=False, indent=2)

    totals = template.get('totals', {})
    logged_meals.append({
        'meal_id': timestamp,
        'description': template.get('meal_description', ''),
        'calories': totals.get('calories', 0),
        'protein_g': totals.get('protein_g', 0),
        'fat_g': totals.get('fat_g', 0),
        'carbs_g': totals.get('carbs_g', 0),
        'fiber_g': totals.get('fiber_g', 0),
        'timestamp': iso_timestamp,
    })

    cal = totals.get('calories', 0)
    print(f'  {time_str}  @{template_name:<20s} {cal:>4} kcal  -> {os.path.basename(outfile)}', file=sys.stderr)

# Output wrapped JSON for iOS Shortcut (base64 will be applied by shell)
wrapped = {'count': len(logged_meals), 'meals': logged_meals}
json.dump(wrapped, sys.stdout, ensure_ascii=False)

total_cal = sum(m['calories'] for m in logged_meals)
print(f'', file=sys.stderr)
print(f'Logged {len(logged_meals)} meals ({total_cal} kcal total) for {date_str}', file=sys.stderr)
" "$PRESET_FILE" "$TEMPLATES_DIR" "$MEALS_DIR" "$DATE" 2>&1 1>/tmp/food-log-batch-wrapped.json

# Output base64 for iOS Shortcut
base64 < /tmp/food-log-batch-wrapped.json

debug "=== END batch === preset=$PRESET_NAME meals logged"
