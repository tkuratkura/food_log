# Food Log - Meal Nutrition Analyzer

A system that analyzes meals (from photos or text descriptions) and estimates comprehensive nutritional information (39 HealthKit-compatible nutrient types) using Claude Code's `/analyze-meal` custom command. Frequently eaten meals can be saved as templates for instant logging without Claude analysis.

## Usage

```
# Image: iCloud Drive inbox (via iOS Shortcut)
/analyze-meal "~/Library/Mobile Documents/com~apple~CloudDocs/FoodLog/inbox/2026-03-09_123000.jpg"

# Image: any file path
/analyze-meal ~/Pictures/lunch.jpg

# Image: paste first, then run
(paste image)
/analyze-meal

# Text: describe what you ate
/analyze-meal 味噌ラーメンと餃子5個
/analyze-meal チキンカレー大盛りとサラダ
/analyze-meal salmon sashimi 5 pieces, miso soup, rice

# Template: skip Claude analysis, log instantly
./scripts/analyze.sh @炒り大豆おやつ

# Preset: log multiple templates at once (e.g., fixed weekday meals)
./scripts/analyze.sh @平日昼間

# Save a template from an existing meal log
./scripts/save-template.sh 2026-03-10_094545 "炒り大豆おやつ"

# Async: submit from iPhone, process in background on Mac
./scripts/submit.sh /path/to/photo.jpg          # Returns ticket ID immediately
./scripts/submit.sh "味噌ラーメン"                # Text analysis (async)
./scripts/submit.sh @大豆の間食                   # Template (still instant)
./scripts/job-status.sh 2026-04-09_123000        # Check job status
./scripts/job-status.sh 2026-04-09_123000 --result  # Get base64 result when done
```

## Data Format

Analysis results are saved to iCloud Drive `FoodLog/results/YYYY-MM-DD_HHMMSS.json` (`~/Library/Mobile Documents/com~apple~CloudDocs/FoodLog/results/`):

```json
{
  "meal_id": "2026-03-09_123000",
  "timestamp": "2026-03-09T12:30:00+09:00",
  "image_path": "/path/to/original/photo.jpg",
  "food_items": [
    {
      "name": "焼き鮭",
      "name_en": "Grilled salmon",
      "quantity": "1切れ (~150g)",
      "portion_g": 150,
      "food_db_search": "さけ しろさけ 焼き",
      "estimation_notes": "Standard single fillet ~150g",
      "confidence": "high",
      "nutrient_source": "food_db",
      "calories": 350,
      "protein_g": 38.2,
      "fat_g": 18.5,
      "carbs_g": 0.1,
      "fiber_g": 0.0,
      "sugar_g": 0.0,
      "saturated_fat_g": 3.2,
      "monounsaturated_fat_g": 5.8,
      "polyunsaturated_fat_g": 7.1,
      "cholesterol_mg": 85.0,
      "sodium_mg": 520.0,
      "potassium_mg": 490.0,
      "calcium_mg": 15.0,
      "iron_mg": 0.5,
      "magnesium_mg": 38.0,
      "phosphorus_mg": 340.0,
      "zinc_mg": 0.8,
      "copper_mg": 0.07,
      "manganese_mg": 0.01,
      "selenium_mcg": 42.0,
      "chromium_mcg": null,
      "molybdenum_mcg": null,
      "iodine_mcg": null,
      "chloride_mg": null,
      "vitamin_a_mcg": 15.0,
      "vitamin_c_mg": 0.0,
      "vitamin_d_mcg": 15.0,
      "vitamin_e_mg": 1.2,
      "vitamin_k_mcg": 0.1,
      "vitamin_b1_mg": 0.25,
      "vitamin_b2_mg": 0.15,
      "vitamin_b6_mg": 0.65,
      "vitamin_b12_mcg": 5.8,
      "niacin_mg": 8.5,
      "folate_mcg": 8.0,
      "pantothenic_acid_mg": 1.5,
      "biotin_mcg": null,
      "caffeine_mg": 0.0,
      "water_ml": 95.0
    }
  ],
  "totals": {
    "calories": 350,
    "protein_g": 38.2,
    "...": "same fields as food_items, summed"
  },
  "meal_description": "焼き鮭定食"
}
```

Nutrients that cannot be reasonably estimated are set to `null`.

**New fields**: `portion_g` (numeric grams), `food_db_search` (formal name for 日本食品標準成分表 lookup), `estimation_notes` (reasoning for portion estimate), `nutrient_source` ("food_db" or "estimated"). After Claude analysis, `scripts/lookup-nutrients.py` cross-references with the food composition DB (`data/food_db/standard_tables.json`) and replaces nutrient estimates with accurate DB values where a match is found.

## Integration

The iCloud `FoodLog/results/*.json` files are:
- Sent to HealthKit via iOS Shortcut (SSH + "Log Health Sample" actions for all non-null nutrients)
- Consumed by the `health_hub` project for Obsidian dashboard integration

## Notes

- Terminal explanations should be in Japanese.
- Code comments, help messages, and scripts should be in English.
- English documentation goes in the `.docs/` directory.
