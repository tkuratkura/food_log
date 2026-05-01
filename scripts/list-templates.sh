#!/bin/bash
# List available meal templates.
# Output format is configurable for both human reading and iOS Shortcut integration.
#
# Usage:
#   ./scripts/list-templates.sh              # Auto-detect: table (TTY) or JSON (pipe/SSH)
#   ./scripts/list-templates.sh json       # Force JSON output
#   ./scripts/list-templates.sh names      # Template names only (newline-separated)

set -euo pipefail

# Ensure Python can output UTF-8 in non-interactive SSH sessions
export PYTHONIOENCODING=utf-8

FOOD_LOG_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES_DIR="$FOOD_LOG_DIR/data/templates"
PRESETS_DIR="$FOOD_LOG_DIR/data/presets"

# Auto-detect: JSON when piped/SSH, table when interactive terminal
if [ $# -ge 1 ]; then
  FORMAT="$1"
elif [ -t 1 ]; then
  FORMAT="table"
else
  FORMAT="json"
fi

if [ ! -d "$TEMPLATES_DIR" ] || [ -z "$(ls -A "$TEMPLATES_DIR" 2>/dev/null)" ]; then
  if [ "$FORMAT" = "json" ] || [ "$FORMAT" = "--json" ]; then
    echo '[]'
  else
    echo "No templates found." >&2
  fi
  exit 0
fi

case "$FORMAT" in
  json|--json)
    # JSON array of {name, description, calories, type} for iOS Shortcut
    python3 -c "
import json, sys, os, glob

templates_dir = sys.argv[1]
presets_dir = sys.argv[2]
result = []
for f in sorted(glob.glob(os.path.join(templates_dir, '*.json'))):
    try:
        with open(f) as fh:
            t = json.load(fh)
        name = os.path.basename(f).replace('.json', '')
        desc = t.get('meal_description', '')
        cal = t.get('totals', {}).get('calories', 0)
        result.append({'name': name, 'description': desc, 'calories': cal, 'type': 'template'})
    except (json.JSONDecodeError, KeyError):
        continue

for f in sorted(glob.glob(os.path.join(presets_dir, '*.json'))):
    try:
        with open(f) as fh:
            p = json.load(fh)
        name = os.path.basename(f).replace('.json', '')
        desc = p.get('description', '')
        meals = p.get('meals', [])
        result.append({'name': name, 'description': desc, 'calories': None, 'type': 'preset', 'meal_count': len(meals)})
    except (json.JSONDecodeError, KeyError):
        continue

print(json.dumps(result, ensure_ascii=False))
" "$TEMPLATES_DIR" "$PRESETS_DIR"
    ;;
  names|--names)
    # Template and preset names, one per line
    for f in "$TEMPLATES_DIR"/*.json; do
      basename "$f" .json
    done
    for f in "$PRESETS_DIR"/*.json; do
      [ -f "$f" ] && basename "$f" .json
    done
    ;;
  *)
    # Human-readable table
    python3 -c "
import json, sys, os, glob

templates_dir = sys.argv[1]
presets_dir = sys.argv[2]
results = []
for f in sorted(glob.glob(os.path.join(templates_dir, '*.json'))):
    try:
        with open(f) as fh:
            t = json.load(fh)
        name = os.path.basename(f).replace('.json', '')
        desc = t.get('meal_description', '')
        cal = t.get('totals', {}).get('calories', 0)
        items = len(t.get('food_items', []))
        results.append((name, f'{cal:>4} kcal  ({items} items)', desc))
    except (json.JSONDecodeError, KeyError):
        continue

presets = []
for f in sorted(glob.glob(os.path.join(presets_dir, '*.json'))):
    try:
        with open(f) as fh:
            p = json.load(fh)
        name = os.path.basename(f).replace('.json', '')
        desc = p.get('description', '')
        meals = p.get('meals', [])
        presets.append((name, f'{len(meals)} meals', desc))
    except (json.JSONDecodeError, KeyError):
        continue

if not results and not presets:
    print('No templates found.', file=sys.stderr)
    sys.exit(0)

all_items = results + presets
name_w = max(len(r[0]) for r in all_items) if all_items else 0

if results:
    print('Templates:')
    for name, info, desc in results:
        print(f'  {name:<{name_w}}  {info}  {desc}')

if presets:
    if results:
        print()
    print('Presets:')
    for name, info, desc in presets:
        print(f'  {name:<{name_w}}  {info}       {desc}')

print(f'\nTotal: {len(results)} templates, {len(presets)} presets')
" "$TEMPLATES_DIR" "$PRESETS_DIR"
    ;;
esac
