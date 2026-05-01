# Food Log - Architecture

## Overview

Food Log is a meal photo nutrition analyzer powered by Claude Code. Users take food photos on their iPhone, which sync to Mac via iCloud. The `/analyze-meal` custom command in Claude Code reads the photo, identifies food items, estimates nutritional content, and saves the results as JSON. Frequently eaten meals can be saved as templates for instant logging without Claude analysis.

## System Flow

```
iPhone (photo) → iOS Shortcut saves to iCloud Drive/FoodLog/inbox/
                                  ↓ (iCloud sync)
                 Mac: ~/Library/Mobile Documents/com~apple~CloudDocs/FoodLog/inbox/
                                  ↓
                        Claude Code: /analyze-meal <path>
                                  ↓
                        Claude identifies foods + estimates portions (with reasoning)
                                  ↓
                        lookup-nutrients.py: cross-reference with 日本食品標準成分表
                        (replaces nutrient estimates with DB values where matched)
                                  ↓
                        iCloud FoodLog/pending/YYYY-MM-DD_HHMMSS.json
                                  ↓ (user confirms via iOS Shortcut)
                        iCloud FoodLog/results/YYYY-MM-DD_HHMMSS.json
                                  ↓
                        health_hub reads JSON (future integration)
```

**Key design decision**: No FastAPI server or backend required. Claude Code itself serves as the analysis engine via a custom slash command.

## iPhone Workflow

### iOS Shortcut Setup

Create an iOS Shortcut named "FoodLog" with these steps:

1. **Receive** input (photo from Share Sheet or camera)
2. **Save File** to `iCloud Drive/FoodLog/inbox/` with filename format `YYYY-MM-DD_HHMMSS.jpg`

Add the shortcut to the Share Sheet so it can be triggered directly from the Photos app.

### Photo Path on Mac

iCloud Drive syncs the photo to:
```
~/Library/Mobile Documents/com~apple~CloudDocs/FoodLog/inbox/<filename>.jpg
```

### SSH Option

If SSH access to Mac is available (e.g., from iPhone terminal apps like Termius), analysis can be triggered remotely:
```bash
ssh mac "cd ~/GIT/food_log && claude '/analyze-meal ~/Library/Mobile\ Documents/com~apple~CloudDocs/FoodLog/inbox/photo.jpg'"
```

## Project Structure

```
food_log/
├── .claude/
│   └── commands/
│       └── analyze-meal.md    # /analyze-meal custom command prompt
├── .docs/
│   ├── architecture.md        # This file
│   └── ios-shortcut-guide.md  # iOS Shortcut setup instructions
├── scripts/
│   ├── analyze.sh             # SSH-callable analysis wrapper script
│   ├── lookup-nutrients.py    # Replace Claude estimates with food composition DB values
│   └── save-template.sh       # Save existing meal log as reusable template
├── data/
│   ├── food_db/
│   │   ├── standard_tables.json  # 日本食品標準成分表 八訂 (2,478 foods, CC BY 4.0)
│   │   └── field_mapping.json    # INFOODS tag → HealthKit field mapping
│   └── templates/             # Meal templates for instant logging
├── CLAUDE.md                  # Project instructions
└── .gitignore
```

## Data Format

Each meal analysis produces a JSON file at iCloud `FoodLog/results/YYYY-MM-DD_HHMMSS.json`:

```json
{
  "meal_id": "2026-03-09_123000",
  "timestamp": "2026-03-09T12:30:00+09:00",
  "image_path": "/path/to/original/photo.jpg",
  "food_items": [
    {
      "name": "焼き鮭",
      "name_en": "Grilled salmon",
      "calories": 350,
      "protein_g": 38.2,
      "fat_g": 18.5,
      "carbs_g": 0.0,
      "quantity": "1切れ (~150g)",
      "confidence": "high"
    }
  ],
  "total_calories": 350,
  "total_protein_g": 38.2,
  "total_fat_g": 18.5,
  "total_carbs_g": 0.0,
  "meal_description": "焼き鮭定食"
}
```

### Field Descriptions

| Field | Type | Description |
|-------|------|-------------|
| `meal_id` | string | Unique ID derived from timestamp (YYYY-MM-DD_HHMMSS) |
| `timestamp` | string | ISO 8601 timestamp with JST timezone |
| `image_path` | string | Absolute path to the original photo |
| `food_items` | array | List of identified food items |
| `food_items[].name` | string | Food name in Japanese |
| `food_items[].name_en` | string | Food name in English |
| `food_items[].calories` | number | Estimated calories (kcal) |
| `food_items[].protein_g` | number | Estimated protein (grams) |
| `food_items[].fat_g` | number | Estimated fat (grams) |
| `food_items[].carbs_g` | number | Estimated carbohydrates (grams) |
| `food_items[].quantity` | string | Portion size description |
| `food_items[].confidence` | string | Estimation confidence: high, medium, or low |
| `total_calories` | number | Sum of all food item calories |
| `total_protein_g` | number | Sum of all food item protein |
| `total_fat_g` | number | Sum of all food item fat |
| `total_carbs_g` | number | Sum of all food item carbohydrates |
| `meal_description` | string | Brief meal description in Japanese |

### Confidence Levels

- **high**: Common, clearly identifiable food with well-known nutritional values
- **medium**: Food is identifiable but portion size is uncertain, or it's a mixed dish
- **low**: Food is partially obscured, unclear, or highly variable in preparation

### Nutritional Reference

Estimates are based on:
- USDA FoodData Central
- Japanese Standard Tables of Food Composition (日本食品標準成分表)

## Templates

Frequently eaten meals can be saved as templates for instant logging without Claude analysis.

### Saving a Template

```bash
# Save an existing meal log as a template
./scripts/save-template.sh <meal_id> <template_name>
./scripts/save-template.sh 2026-03-10_094545 "炒り大豆おやつ"
```

Templates are stored in `data/templates/<name>.json` containing `food_items`, `totals`, and `meal_description`.

### Using a Template

```bash
# Use @ prefix to log from template (no Claude analysis, instant)
./scripts/analyze.sh @炒り大豆おやつ
```

The output JSON has `input_type: "template"` and follows the same format as Claude-analyzed meals, so the iOS Shortcut HealthKit flow works without changes.

## HealthKit Integration via iOS Shortcut + SSH

The primary flow for recording nutrition data to Apple HealthKit:

```
iPhone: Photo → iOS Shortcut "FoodLog"
  ├─ Pick meal time (defaults to now, user can change)
  ├─ Save photo to iCloud Drive/FoodLog/inbox/
  ├─ SSH to Mac → run scripts/analyze.sh --time <meal_time>
  ├─ Receive JSON result
  ├─ Show confirmation (meal description + calories)
  │   └─ Cancel → SSH rm JSON on Mac → stop
  ├─ Log to HealthKit (up to 39 nutrient types)
  └─ Add completed reminder to "FoodLog" list (meal history)
```

### Components

- **`scripts/analyze.sh`**: Mac-side wrapper that runs Claude Code analysis and outputs JSON
- **iOS Shortcut "FoodLog"**: Orchestrates the entire flow from photo to HealthKit
- **iCloud Drive `FoodLog/results/`**: Analysis results synced back for iOS access

See [ios-shortcut-guide.md](ios-shortcut-guide.md) for detailed setup instructions.

### HealthKit Data Types Recorded

Up to 39 dietary nutrient types are logged to HealthKit. Nutrients that cannot be estimated from the photo are set to `null` and skipped.

| Category | HealthKit Types | JSON Fields |
|----------|----------------|-------------|
| **Macros (10)** | Energy, Protein, Fat (total/sat/mono/poly), Carbs, Fiber, Sugar, Cholesterol | `calories`, `protein_g`, `fat_g`, `saturated_fat_g`, `monounsaturated_fat_g`, `polyunsaturated_fat_g`, `carbs_g`, `fiber_g`, `sugar_g`, `cholesterol_mg` |
| **Minerals (14)** | Na, K, Ca, Fe, Mg, P, Zn, Cu, Mn, Se, Cr, Mo, I, Cl | `sodium_mg`, `potassium_mg`, `calcium_mg`, `iron_mg`, `magnesium_mg`, `phosphorus_mg`, `zinc_mg`, `copper_mg`, `manganese_mg`, `selenium_mcg`, `chromium_mcg`, `molybdenum_mcg`, `iodine_mcg`, `chloride_mg` |
| **Vitamins (13)** | A, C, D, E, K, B1, B2, B6, B12, Niacin, Folate, Pantothenic acid, Biotin | `vitamin_a_mcg`, `vitamin_c_mg`, `vitamin_d_mcg`, `vitamin_e_mg`, `vitamin_k_mcg`, `vitamin_b1_mg`, `vitamin_b2_mg`, `vitamin_b6_mg`, `vitamin_b12_mcg`, `niacin_mg`, `folate_mcg`, `pantothenic_acid_mg`, `biotin_mcg` |
| **Other (2)** | Caffeine, Water | `caffeine_mg`, `water_ml` |

## health_hub Integration (Future)

The `health_hub` project will consume iCloud `FoodLog/results/*.json` files to:

1. **Obsidian**: Embed nutrition data in daily notes as `![[Nutrition/FoodLog#date]]`
2. **Health Dashboard**: Combine with weight, sleep, and step data for comprehensive health tracking

The JSON format is designed to be stable and easily parseable by downstream consumers.
