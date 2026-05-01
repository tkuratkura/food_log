#!/bin/bash
# Save an existing meal log as a reusable template.
#
# Usage:
#   ./scripts/save-template.sh <meal_id> <template_name>
#   ./scripts/save-template.sh 2026-03-10_094545 "炒り大豆おやつ"
#
# Templates are saved to data/templates/<name>.json
# Use with analyze.sh: ./scripts/analyze.sh @炒り大豆おやつ

set -euo pipefail

FOOD_LOG_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES_DIR="$FOOD_LOG_DIR/data/templates"
MEALS_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/FoodLog/results"

if [ $# -lt 2 ]; then
  echo "Usage: $0 <meal_id> <template_name>" >&2
  echo "Example: $0 2026-03-10_094545 \"炒り大豆おやつ\"" >&2
  echo "" >&2
  # List existing templates
  if [ -d "$TEMPLATES_DIR" ] && [ "$(ls -A "$TEMPLATES_DIR" 2>/dev/null)" ]; then
    echo "Existing templates:" >&2
    for f in "$TEMPLATES_DIR"/*.json; do
      name=$(basename "$f" .json)
      desc=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('meal_description',''))" "$f" 2>/dev/null || echo "")
      echo "  @${name}  ${desc}" >&2
    done
  fi
  exit 1
fi

MEAL_ID="$1"
TEMPLATE_NAME="$2"

# Find the meal log
MEAL_FILE="$MEALS_DIR/${MEAL_ID}.json"
if [ ! -f "$MEAL_FILE" ]; then
  echo "Error: Meal log not found: $MEAL_FILE" >&2
  exit 1
fi

mkdir -p "$TEMPLATES_DIR"

# Extract food_items and meal_description from the meal log
python3 -c "
import json, sys

with open(sys.argv[1]) as f:
    meal = json.load(f)

template = {
    'template_name': sys.argv[2],
    'food_items': meal['food_items'],
    'totals': meal['totals'],
    'meal_description': meal.get('meal_description', '')
}

with open(sys.argv[3], 'w') as f:
    json.dump(template, f, ensure_ascii=False, indent=2)

print(f'Template saved: {sys.argv[3]}')
print(f'  Name: {sys.argv[2]}')
print(f'  Items: {len(meal[\"food_items\"])}')
print(f'  Calories: {meal[\"totals\"][\"calories\"]}')
" "$MEAL_FILE" "$TEMPLATE_NAME" "$TEMPLATES_DIR/${TEMPLATE_NAME}.json"
