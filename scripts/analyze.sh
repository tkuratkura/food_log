#!/bin/bash
# Analyze a meal from a photo, text description, or template using Claude Code.
# Outputs JSON with full nutritional profile (39 HealthKit-compatible nutrient types).
#
# Usage:
#   ./scripts/analyze.sh /path/to/photo.jpg                    # Image analysis
#   ./scripts/analyze.sh /path/to/photo.jpg "100ml小鉢"         # Image + notes
#   ./scripts/analyze.sh "味噌ラーメンと餃子5個"                   # Text analysis
#   ./scripts/analyze.sh @炒り大豆おやつ                          # Template (no Claude)
#   ./scripts/analyze.sh --time "2026-03-16_120000" "カレー"     # Custom meal time
#   ./scripts/analyze.sh                                       # Latest photo in iCloud inbox

set -euo pipefail

# Ensure claude is in PATH for non-interactive SSH sessions
export PATH="$HOME/.local/bin:$PATH"
# Set locale for cron (LANG is unset in cron environment)
export LANG="${LANG:-en_US.UTF-8}"

FOOD_LOG_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Debug log for diagnosing SSH/iOS Shortcut issues
DEBUG_LOG="$FOOD_LOG_DIR/data/debug.log"
debug() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$DEBUG_LOG"; }
debug "=== START === args=$* shell=$SHELL tty=$(tty 2>/dev/null || echo none) LANG=${LANG:-unset}"

# Load environment variables for non-interactive authentication
if [ -f "$FOOD_LOG_DIR/.env" ]; then
  ENV_VARS=$(grep -v '^#' "$FOOD_LOG_DIR/.env" | grep '=' | xargs 2>/dev/null) || true
  [ -n "$ENV_VARS" ] && export $ENV_VARS
fi
ICLOUD_BASE="$HOME/Library/Mobile Documents/com~apple~CloudDocs/FoodLog"
INBOX="$ICLOUD_BASE/inbox"
PENDING_DIR="$FOOD_LOG_DIR/data/pending"
MEALS_DIR="$ICLOUD_BASE/results"

TEMPLATES_DIR="$FOOD_LOG_DIR/data/templates"
PRESETS_DIR="$FOOD_LOG_DIR/data/presets"

# --- Queue worker (watch / queue modes) ---
QUEUE_DIR="$FOOD_LOG_DIR/data/queue"
PROCESSING_DIR="$QUEUE_DIR/processing"
DONE_DIR="$QUEUE_DIR/done"
FAILED_DIR="$QUEUE_DIR/failed"
WATCH_LOCK="$QUEUE_DIR/.watcher.lock"
WATCH_INTERVAL="${FOOD_LOG_WATCH_INTERVAL:-300}"
RETRY_AFTER="${FOOD_LOG_RETRY_AFTER:-10}"

acquire_watch_lock() {
  if [ -f "$WATCH_LOCK" ]; then
    local lock_pid
    lock_pid=$(cat "$WATCH_LOCK" 2>/dev/null || echo "")
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
      debug "[watch] watcher already running (PID $lock_pid), exiting"
      exit 0
    fi
    debug "[watch] removing stale lock (PID $lock_pid)"
    rm -f "$WATCH_LOCK"
  fi
  echo $$ > "$WATCH_LOCK"
  trap 'rm -f "$WATCH_LOCK"' EXIT
}

recover_orphans() {
  local orphan
  while IFS= read -r orphan; do
    [ -z "$orphan" ] && continue
    debug "[watch] recovering orphan: $(basename "$orphan")"
    mv "$orphan" "$QUEUE_DIR/$(basename "$orphan")"
  done < <(find "$PROCESSING_DIR" -maxdepth 1 -name '*.json' -type f 2>/dev/null)
}

process_next_ticket() {
  local job
  job=$(find "$QUEUE_DIR" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null \
    | xargs -0 ls -tr 2>/dev/null \
    | head -1 || true)
  [ -z "$job" ] && return 1

  local ticket_id
  ticket_id=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['ticket_id'])" "$job")
  local job_basename="${ticket_id}.json"

  debug "[watch] processing ticket: $ticket_id"
  mv "$job" "$PROCESSING_DIR/$job_basename"

  # Build args list (preserves quoting through shlex)
  local args_str
  args_str=$(python3 -c "
import json, shlex, sys
job = json.load(open(sys.argv[1]))
print(' '.join(shlex.quote(a) for a in job['args']))
" "$PROCESSING_DIR/$job_basename")

  local start_time
  start_time=$(date +%s)
  local output=""
  local exit_code=0

  # Single attempt + 1 retry with short backoff (no more 25-min lock blocking)
  output=$(eval "bash $0 $args_str" 2>>"$DEBUG_LOG") || exit_code=$?
  if [ $exit_code -ne 0 ] || [ -z "$output" ]; then
    debug "[watch] ticket $ticket_id attempt 1 failed (exit=$exit_code), retry in ${RETRY_AFTER}s"
    sleep "$RETRY_AFTER"
    output=""
    exit_code=0
    output=$(eval "bash $0 $args_str" 2>>"$DEBUG_LOG") || exit_code=$?
  fi

  local end_time duration completed_at
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  completed_at=$(date +%Y-%m-%dT%H:%M:%S+09:00)

  local tmp_output="/tmp/food-log-watch-output-${ticket_id}.txt"

  if [ $exit_code -eq 0 ] && [ -n "$output" ]; then
    debug "[watch] ticket $ticket_id done in ${duration}s"
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
" "$PROCESSING_DIR/$job_basename" "$DONE_DIR/$job_basename" "$completed_at" "$duration" "$tmp_output"
    rm -f "$PROCESSING_DIR/$job_basename" "$tmp_output"
  else
    debug "[watch] ticket $ticket_id FAILED (exit=$exit_code, duration=${duration}s)"
    python3 -c "
import json, sys
job = json.load(open(sys.argv[1]))
job['status'] = 'failed'
job['failed_at'] = sys.argv[3]
job['duration_s'] = int(sys.argv[4])
job['exit_code'] = int(sys.argv[5])
with open(sys.argv[2], 'w') as f:
    json.dump(job, f, ensure_ascii=False, indent=2)
" "$PROCESSING_DIR/$job_basename" "$FAILED_DIR/$job_basename" "$completed_at" "$duration" "$exit_code"
    rm -f "$PROCESSING_DIR/$job_basename" "$tmp_output"
  fi

  return 0
}

run_watch_loop() {
  mkdir -p "$PROCESSING_DIR" "$DONE_DIR" "$FAILED_DIR"
  acquire_watch_lock
  recover_orphans
  debug "[watch] === WATCHER START === PID=$$ interval=${WATCH_INTERVAL}s"
  while true; do
    if process_next_ticket; then
      continue   # Drain queue without sleeping between tickets
    fi
    sleep "$WATCH_INTERVAL"
  done
}

run_queue_drain() {
  mkdir -p "$PROCESSING_DIR" "$DONE_DIR" "$FAILED_DIR"
  acquire_watch_lock
  recover_orphans
  debug "[queue] === DRAIN START ==="
  while process_next_ticket; do :; done
  debug "[queue] === DRAIN END (queue empty) ==="
}

# --- Mode dispatch (early exit for watch/queue modes) ---
case "${1:-}" in
  --watch) run_watch_loop; exit 0 ;;
  --queue) run_queue_drain; exit 0 ;;
esac

# Generate TIMESTAMP and ISO_TIMESTAMP from --time or current time
generate_timestamps() {
  if [ -n "$CUSTOM_TIME" ]; then
    TIMESTAMP="$CUSTOM_TIME"
    ISO_TIMESTAMP=$(python3 -c "from datetime import datetime; d=datetime.strptime('$CUSTOM_TIME','%Y-%m-%d_%H%M%S'); print(d.strftime('%Y-%m-%dT%H:%M:%S+09:00'))")
  else
    TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
    ISO_TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S+09:00)
  fi
}

# Parse --time option (must appear before other arguments)
CUSTOM_TIME=""
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --time)
      CUSTOM_TIME="$2"
      shift 2
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done
set -- "${args[@]+"${args[@]}"}"
debug "parsed options: CUSTOM_TIME='$CUSTOM_TIME' remaining_args=$*"

# Resolve template name from argument
# Supports: @name, ＠name (fullwidth), or exact template name without prefix
resolve_template() {
  local input="$1"
  # Trim leading/trailing whitespace
  input="$(echo "$input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  # Strip @ or ＠ prefix
  local name="$(echo "$input" | sed 's/^[@＠]//')"
  local file="$TEMPLATES_DIR/${name}.json"
  if [ -f "$file" ]; then
    echo "$name"
    return 0
  fi
  return 1
}

# Resolve @name: check template first, then preset
TEMPLATE_MATCH=false
PRESET_MATCH=false
if [ $# -ge 1 ]; then
  TEMPLATE_NAME="$(resolve_template "$1")" && TEMPLATE_MATCH=true || TEMPLATE_MATCH=false
  debug "resolve_template '$1' → match=$TEMPLATE_MATCH name='${TEMPLATE_NAME:-}'"

  # If not a template, check if it's a preset
  if [ "$TEMPLATE_MATCH" = false ]; then
    STRIPPED="$(echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^[@＠]//')"
    if [ -f "$PRESETS_DIR/${STRIPPED}.json" ]; then
      PRESET_MATCH=true
      PRESET_NAME="$STRIPPED"
      debug "preset match: $PRESET_NAME"
    fi
  fi
fi

if [ "$TEMPLATE_MATCH" = true ]; then
  TEMPLATE_FILE="$TEMPLATES_DIR/${TEMPLATE_NAME}.json"
  debug "template mode: file=$TEMPLATE_FILE"

  # Generate meal JSON from template (no Claude analysis needed, skip pending)
  mkdir -p "$MEALS_DIR"
  generate_timestamps
  OUTFILE="$MEALS_DIR/${TIMESTAMP}.json"

  python3 -c "
import json, sys

with open(sys.argv[1]) as f:
    template = json.load(f)

meal = {
    'meal_id': sys.argv[2],
    'timestamp': sys.argv[3],
    'image_path': None,
    'input_type': 'template',
    'input_text': '@' + sys.argv[4],
    'food_items': template['food_items'],
    'totals': template['totals'],
    'meal_description': template.get('meal_description', '')
}

with open(sys.argv[5], 'w') as f:
    json.dump(meal, f, ensure_ascii=False, indent=2)
" "$TEMPLATE_FILE" "$TIMESTAMP" "$ISO_TIMESTAMP" "$TEMPLATE_NAME" "$OUTFILE"

  debug "template output: $OUTFILE ($(wc -c < "$OUTFILE") bytes)"
  debug "=== END template ==="

  # Wrap single meal in {count, meals[]} for FoodLog:HealthKit module compatibility
  TMPWRAP="/tmp/food-log-template-wrapped.json"
  python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    meal = json.load(f)
wrapped = {'count': 1, 'meals': [{
    'meal_id': meal['meal_id'],
    'description': meal.get('meal_description', ''),
    'calories': meal.get('totals', {}).get('calories', 0),
    'protein_g': meal.get('totals', {}).get('protein_g', 0),
    'fat_g': meal.get('totals', {}).get('fat_g', 0),
    'carbs_g': meal.get('totals', {}).get('carbs_g', 0),
    'fiber_g': meal.get('totals', {}).get('fiber_g', 0),
    'timestamp': meal.get('timestamp', ''),
}]}
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    json.dump(wrapped, f, ensure_ascii=False)
" "$OUTFILE" "$TMPWRAP"
  base64 < "$TMPWRAP"
  exit 0
fi

# Preset mode: log all meals in the preset at their specified times
if [ "$PRESET_MATCH" = true ]; then
  PRESET_FILE="$PRESETS_DIR/${PRESET_NAME}.json"
  DATE="$(date +%Y-%m-%d)"
  [ -n "$CUSTOM_TIME" ] && DATE="${CUSTOM_TIME:0:10}"
  debug "preset mode: file=$PRESET_FILE date=$DATE TEMPLATES_DIR=$TEMPLATES_DIR MEALS_DIR=$MEALS_DIR cwd=$(pwd)"
  mkdir -p "$MEALS_DIR"

  if [ ! -w "$MEALS_DIR" ]; then
    debug "ERROR: MEALS_DIR not writable: $MEALS_DIR"
    echo "{\"error\":\"results directory not writable: $MEALS_DIR\"}" >&2
    exit 1
  fi

  EXPECTED_COUNT=$(python3 -c "import json; print(len(json.load(open('$PRESET_FILE'))['meals']))" 2>>"$DEBUG_LOG" || echo 0)
  debug "preset expects $EXPECTED_COUNT meals"

  # Emit one base64 line per meal in {count:1, meals:[...]} format.
  # Each line matches single-template output, so Foodlog:HealthKit works as-is.
  # Shortcut splits by newline and loops.
  # stderr captured to debug.log so silent failures become visible.
  PRESET_EXIT=0
  python3 -c "
import json, sys, os, base64

preset_file = sys.argv[1]
templates_dir = sys.argv[2]
meals_dir = sys.argv[3]
date_str = sys.argv[4]

def log(msg):
    print('[preset.py] ' + msg, file=sys.stderr)

log(f'preset_file={preset_file}')
log(f'templates_dir={templates_dir} exists={os.path.isdir(templates_dir)}')
log(f'meals_dir={meals_dir} writable={os.access(meals_dir, os.W_OK)}')
log(f'date_str={date_str}')

with open(preset_file) as f:
    preset = json.load(f)

total = len(preset['meals'])
log(f'preset has {total} meals')

time_counter = {}
written = 0
skipped = 0

for entry in preset['meals']:
    template_name = entry['template']
    time_str = entry['time']

    tpl_file = os.path.join(templates_dir, f'{template_name}.json')
    if not os.path.exists(tpl_file):
        log(f'MISSING template: {tpl_file}')
        skipped += 1
        continue

    with open(tpl_file) as f:
        template = json.load(f)

    offset = time_counter.get(time_str, 0)
    time_counter[time_str] = offset + 1
    hh, mm = time_str.split(':')
    timestamp = f'{date_str}_{hh}{mm}{offset:02d}'
    iso_timestamp = f'{date_str}T{hh}:{mm}:{offset:02d}+09:00'

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
    try:
        with open(outfile, 'w') as f:
            json.dump(meal, f, ensure_ascii=False, indent=2)
    except Exception as e:
        log(f'FAILED write {outfile}: {e!r}')
        raise

    if not os.path.exists(outfile):
        log(f'FILE MISSING after write: {outfile}')
        raise RuntimeError('file missing after write: ' + outfile)

    size = os.path.getsize(outfile)
    log(f'wrote {outfile} ({size} bytes)')
    written += 1

    totals = template.get('totals', {})
    wrapped = {'count': 1, 'meals': [{
        'meal_id': timestamp,
        'description': template.get('meal_description', ''),
        'calories': totals.get('calories', 0),
        'protein_g': totals.get('protein_g', 0),
        'fat_g': totals.get('fat_g', 0),
        'carbs_g': totals.get('carbs_g', 0),
        'fiber_g': totals.get('fiber_g', 0),
        'timestamp': iso_timestamp,
    }]}
    b64 = base64.b64encode(json.dumps(wrapped, ensure_ascii=False).encode()).decode()
    print(b64)

log(f'DONE wrote={written} skipped={skipped} total={total}')

if written == 0:
    log('ERROR: wrote 0 files')
    sys.exit(2)
if written < total:
    log(f'ERROR: wrote {written} of {total}')
    sys.exit(3)
" "$PRESET_FILE" "$TEMPLATES_DIR" "$MEALS_DIR" "$DATE" 2>>"$DEBUG_LOG" || PRESET_EXIT=$?

  if [ $PRESET_EXIT -ne 0 ]; then
    debug "preset python FAILED (exit=$PRESET_EXIT) — see [preset.py] lines above"
    echo "{\"error\":\"preset processing failed (exit=$PRESET_EXIT)\"}" >&2
    exit $PRESET_EXIT
  fi

  # Final sanity check: at least one file must exist on disk for this date
  WRITTEN_COUNT=$(find "$MEALS_DIR" -maxdepth 1 -name "${DATE}_*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
  debug "preset post-check: $WRITTEN_COUNT files matching ${DATE}_*.json in MEALS_DIR"

  if [ "$WRITTEN_COUNT" -lt 1 ]; then
    debug "ERROR: no files on disk for date=$DATE despite python success"
    echo "{\"error\":\"no preset files written for $DATE\"}" >&2
    exit 1
  fi

  debug "=== END preset === (wrote $WRITTEN_COUNT files)"
  exit 0
fi

debug "not a template, proceeding to analysis mode"

PHOTO_PATH=""
NOTES=""
MEAL_TEXT=""
INPUT_TYPE=""

# Support stdin input: echo "味噌汁(わかめ)" | ./scripts/analyze.sh
if [ $# -eq 0 ] && [ ! -t 0 ]; then
  STDIN_TEXT=$(cat)
  if [ -n "$STDIN_TEXT" ]; then
    set -- "$STDIN_TEXT"
  fi
fi

# Parse arguments: separate file path from notes/text
for arg in "$@"; do
  if [ -z "$PHOTO_PATH" ] && [ -f "$arg" ]; then
    PHOTO_PATH="$arg"
  elif [ -z "$PHOTO_PATH" ] && echo "$arg" | grep -qiE '\.(jpg|jpeg|png|heic)$'; then
    # Looks like a file path but doesn't exist yet — wait for iCloud sync
    debug "waiting for file: $arg"
    for i in $(seq 1 30); do
      [ -f "$arg" ] && break
      sleep 1
    done
    if [ -f "$arg" ]; then
      PHOTO_PATH="$arg"
    else
      echo "{\"error\": \"File not found after 30s: ${arg}\"}" >&2
      exit 1
    fi
  elif [ -z "$PHOTO_PATH" ] && echo "$arg" | grep -qiE '\.(jpg|jpeg|png|heic)'; then
    # Image extension found mid-string — split on fullwidth space (U+3000)
    # Handles iOS Shortcut joining path + notes: "photo.jpg　牛丼弁当"
    FILE_PART="$(echo "$arg" | sed 's/　.*//')"
    NOTE_PART="$(echo "$arg" | sed -n 's/^[^　]*　//p')"
    debug "split combined arg: file='$FILE_PART' note='$NOTE_PART'"
    if [ -f "$FILE_PART" ]; then
      PHOTO_PATH="$FILE_PART"
      [ -n "$NOTE_PART" ] && NOTES="${NOTES:+$NOTES }$NOTE_PART"
    else
      # Wait for iCloud sync
      debug "waiting for split file: $FILE_PART"
      for i in $(seq 1 30); do
        [ -f "$FILE_PART" ] && break
        sleep 1
      done
      if [ -f "$FILE_PART" ]; then
        PHOTO_PATH="$FILE_PART"
        [ -n "$NOTE_PART" ] && NOTES="${NOTES:+$NOTES }$NOTE_PART"
      else
        echo "{\"error\": \"File not found after 30s: ${FILE_PART}\"}" >&2
        exit 1
      fi
    fi
  elif [ -n "$PHOTO_PATH" ]; then
    # Additional args after image path are notes (skip stray "echo ok" etc.)
    case "$arg" in echo|ok|true|false) continue ;; esac
    NOTES="${NOTES:+$NOTES }$arg"
  else
    # No file path yet and not a file → accumulate as text (skip stray "echo ok" etc.)
    case "$arg" in echo|ok|true|false) continue ;; esac
    MEAL_TEXT="${MEAL_TEXT:+$MEAL_TEXT }$arg"
  fi
done

# Determine input type
debug "arg parsing done: PHOTO_PATH='$PHOTO_PATH' MEAL_TEXT='$MEAL_TEXT'"
if [ -n "$PHOTO_PATH" ]; then
  INPUT_TYPE="image"
elif [ -n "$MEAL_TEXT" ]; then
  INPUT_TYPE="text"
else
  # No input: find latest photo in inbox
  PHOTO_PATH=$(find "$INBOX" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.heic' \) -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null \
    | head -1)
  if [ -z "$PHOTO_PATH" ]; then
    echo '{"error": "No photos found in inbox and no text provided"}' >&2
    exit 1
  fi
  INPUT_TYPE="image"
fi

# Ensure pending directory exists
mkdir -p "$PENDING_DIR"

generate_timestamps

# Copy image to local if possible; otherwise Claude reads iCloud path directly (has FDA)
ORIGINAL_PHOTO_PATH="$PHOTO_PATH"
LOCAL_PHOTO=""
if [ "$INPUT_TYPE" = "image" ]; then
  LOCAL_PHOTO="$FOOD_LOG_DIR/.tmp_photo_${TIMESTAMP}.jpg"
  if cp "$PHOTO_PATH" "$LOCAL_PHOTO" 2>/dev/null; then
    PHOTO_PATH="$LOCAL_PHOTO"
  else
    LOCAL_PHOTO=""
  fi
fi

# Build prompt based on input type
NOTES_PROMPT=""
if [ -n "$NOTES" ]; then
  NOTES_PROMPT="

The user provided supplementary notes: \"${NOTES}\"
IMPORTANT: These notes are ONLY for adjusting portion sizes, container dimensions, or cooking methods.
Do NOT use notes to determine what foods are present — always identify foods from the image itself.
If the notes mention a food name, treat it as a hint for disambiguation only (e.g., distinguishing similar-looking dishes)."
fi

if [ "$INPUT_TYPE" = "image" ]; then
  ANALYSIS_PROMPT="STEP 1: Read the image file at '${PHOTO_PATH}' using the Read tool.

STEP 2 — TEXT READING (DO THIS FIRST, BEFORE ANY ANALYSIS):
After reading the image, transcribe ALL visible text on the packaging/label exactly as printed.
Include: product name, brand, weight, price, and ALL nutritional information (栄養成分表示).
Output the transcription before proceeding. If no text is visible, say so and skip to Step 3.

STEP 3 — FOOD IDENTIFICATION:
Identify all food items by visually analyzing the image. The image is your primary source of truth.${NOTES_PROMPT}"
  IMAGE_PATH_JSON="\"${ORIGINAL_PHOTO_PATH}\""
  INPUT_TYPE_JSON="\"image\""
  INPUT_TEXT_JSON="null"
else
  ANALYSIS_PROMPT="Analyze the following meal described in text: ${MEAL_TEXT}
Assume standard Japanese portion sizes unless quantities are specified.${NOTES_PROMPT}"
  IMAGE_PATH_JSON="null"
  INPUT_TYPE_JSON="\"text\""
  INPUT_TEXT_JSON="\"${MEAL_TEXT}\""
fi

# Run Claude Code in non-interactive mode
OUTFILE="$PENDING_DIR/${TIMESTAMP}.json"
CLAUDE_STDOUT="/tmp/food-log-claude-${TIMESTAMP}.log"
debug "calling claude: INPUT_TYPE=$INPUT_TYPE OUTFILE=$OUTFILE MEAL_TEXT='${MEAL_TEXT:-}'"
cd "$FOOD_LOG_DIR"

# Build the full prompt
FULL_PROMPT="${ANALYSIS_PROMPT}

You are an expert nutritionist. Provide a FULL nutritional profile.

STEP 4 — NUTRITION LABEL HANDLING:
If you found a nutrition facts label (栄養成分表示) in Step 2:
- Use the EXACT product name and nutrient values you transcribed. Do NOT substitute with guesses.
- Set nutrient_source to \"label\", food_db_search to null, confidence to \"high\".
- Convert 食塩相当量 (g) to sodium_mg by multiplying by 393.4.
- For nutrients NOT on the label, you may estimate them. Note which values are from label vs estimated.
- If you could NOT read the label text clearly in Step 2, set nutrient_source to \"estimated\" instead.

STEP 5 — NUTRITIONAL ANALYSIS:
1. Identify each food item with Japanese and English names
2. For each food item, estimate portion size in grams (portion_g) and explain your reasoning in estimation_notes
3. For each food item, provide food_db_search: the formal name as it appears in 日本食品標準成分表 (八訂)
   Examples: \"こめ 水稲めし 精白米 うるち米\", \"鶏卵 全卵 ゆで\", \"だいず 納豆類 糸引き納豆\"
   For composite dishes (curry, ramen, stir-fry etc.), set food_db_search to null
4. Estimate ALL nutrients: calories, protein, fat (total/saturated/mono/poly), carbs, fiber, sugar,
   cholesterol, sodium, potassium, calcium, iron, magnesium, phosphorus, zinc, copper, manganese,
   selenium, vitamins (A, C, D, E, K, B1, B2, B6, B12, niacin, folate, pantothenic acid),
   caffeine, and water content
5. Base estimates on USDA FoodData Central and Japanese Standard Tables of Food Composition
6. Set nutrients that cannot be reasonably estimated to null
7. Calculate totals (sum non-null values; if all null, total is null)

Save the result as JSON to ${OUTFILE} using the Write tool.
The JSON structure:
{
  \"meal_id\": \"${TIMESTAMP}\",
  \"timestamp\": \"${ISO_TIMESTAMP}\",
  \"image_path\": ${IMAGE_PATH_JSON},
  \"input_type\": ${INPUT_TYPE_JSON},
  \"input_text\": ${INPUT_TEXT_JSON},
  \"food_items\": [{\"name\":\"JP name\",\"name_en\":\"EN name\",\"quantity\":\"portion desc\",
    \"portion_g\":0,\"food_db_search\":\"formal name or null\",\"estimation_notes\":\"reasoning\",
    \"confidence\":\"high|medium|low\",
    \"calories\":0,\"protein_g\":0,\"fat_g\":0,\"carbs_g\":0,\"fiber_g\":0,\"sugar_g\":0,
    \"saturated_fat_g\":0,\"monounsaturated_fat_g\":0,\"polyunsaturated_fat_g\":0,\"cholesterol_mg\":0,
    \"sodium_mg\":0,\"potassium_mg\":0,\"calcium_mg\":0,\"iron_mg\":0,\"magnesium_mg\":0,\"phosphorus_mg\":0,
    \"zinc_mg\":0,\"copper_mg\":0,\"manganese_mg\":0,\"selenium_mcg\":0,
    \"chromium_mcg\":null,\"molybdenum_mcg\":null,\"iodine_mcg\":null,\"chloride_mg\":null,
    \"vitamin_a_mcg\":0,\"vitamin_c_mg\":0,\"vitamin_d_mcg\":0,\"vitamin_e_mg\":0,\"vitamin_k_mcg\":0,
    \"vitamin_b1_mg\":0,\"vitamin_b2_mg\":0,\"vitamin_b6_mg\":0,\"vitamin_b12_mcg\":0,
    \"niacin_mg\":0,\"folate_mcg\":0,\"pantothenic_acid_mg\":0,\"biotin_mcg\":null,
    \"caffeine_mg\":0,\"water_ml\":0}],
  \"totals\": { ...same nutrient fields summed across food_items... },
  \"meal_description\": \"日本語の説明\"
}"

# Run claude (default model — opus disabled due to Claude Code #42649)
CLAUDE_EXIT=0
echo "$FULL_PROMPT" | claude -p --allowedTools Read,Write,Bash > "$CLAUDE_STDOUT" 2>> "$DEBUG_LOG" || CLAUDE_EXIT=$?

debug "claude exited (code=$CLAUDE_EXIT), checking output"
# Log Claude stdout for diagnosis (first 500 chars)
if [ -f "$CLAUDE_STDOUT" ]; then
  debug "claude stdout (truncated): $(head -c 500 "$CLAUDE_STDOUT")"
  rm -f "$CLAUDE_STDOUT"
fi

# Exit with Claude's exit code if it failed
if [ $CLAUDE_EXIT -ne 0 ]; then
  [ -n "${LOCAL_PHOTO:-}" ] && rm -f "$LOCAL_PHOTO"
  exit $CLAUDE_EXIT
fi

# Clean up temp image (original inbox cleanup handled by process-pending.sh via SSH)
if [ "$INPUT_TYPE" = "image" ] && [ -n "$LOCAL_PHOTO" ]; then
  rm -f "$LOCAL_PHOTO"
fi

# Replace Claude's nutrient estimates with food composition DB values where possible
if [ -f "$OUTFILE" ]; then
  debug "running food DB lookup on $OUTFILE"
  python3 "$FOOD_LOG_DIR/scripts/lookup-nutrients.py" "$OUTFILE" 2>> "$DEBUG_LOG" || true
  debug "food DB lookup complete"
fi

# Output base64-encoded JSON for iOS Shortcut to decode
if [ -f "$OUTFILE" ]; then
  base64 < "$OUTFILE"
else
  echo "ERROR" >&2
  exit 1
fi
