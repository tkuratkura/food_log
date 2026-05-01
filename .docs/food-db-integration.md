# Food Composition Database Integration

## Overview

Nutritional values from Claude's analysis are cross-referenced with the **Japanese Standard Tables of Food Composition (日本食品標準成分表 八訂)** to improve accuracy. Claude focuses on food identification and portion estimation, while the database provides precise per-100g nutritional values.

## Data Source

- **Repository**: [katoharu432/standards-tables-of-food-composition-in-japan](https://github.com/katoharu432/standards-tables-of-food-composition-in-japan)
- **License**: CC BY 4.0
- **Foods**: 2,478 items
- **Nutrients**: 52+ fields per item (per 100g edible portion)
- **Local path**: `data/food_db/standard_tables.json`

## How It Works

### Analysis Flow

```
1. Claude analyzes meal (image or text)
   → identifies food items
   → estimates portion_g with estimation_notes (reasoning)
   → provides food_db_search (formal name for DB lookup)
   → estimates all nutrients as fallback

2. lookup-nutrients.py post-processes the JSON
   → for each food_item with food_db_search:
     → fuzzy matches against standard_tables.json foodName
     → if match score ≥ 0.35: replaces nutrients with DB values × portion_g/100
     → if no match: keeps Claude's estimates
   → recalculates totals
   → adds nutrient_source: "food_db" or "estimated"
```

### New JSON Fields

| Field | Type | Description |
|-------|------|-------------|
| `portion_g` | number | Estimated portion weight in grams |
| `food_db_search` | string/null | Formal name for DB lookup (null for composite dishes) |
| `estimation_notes` | string | Reasoning for portion estimate |
| `nutrient_source` | string | "food_db" or "estimated" (set by lookup script) |
| `food_db_id` | number | Matched food ID in standard tables (if matched) |
| `food_db_name` | string | Matched food name (if matched) |
| `food_db_score` | number | Match confidence score 0.0-1.0 (if matched) |

### DB Coverage

The standard tables cover **single ingredients** well:
- Rice, noodles, bread (grains)
- Meat, fish, eggs
- Vegetables, fruits
- Dairy, tofu, natto
- Seasonings

**Not covered** (falls back to Claude estimates):
- Composite dishes (curry, ramen, stir-fry)
- Restaurant-specific items
- Processed/branded foods

### Nutrients Not in DB

These are always Claude estimates (DB doesn't have these fields):
- `sugar_g` (糖質)
- `saturated_fat_g`, `monounsaturated_fat_g`, `polyunsaturated_fat_g` (fatty acid breakdown)
- `chloride_mg`
- `caffeine_mg`

## Field Mapping

See `data/food_db/field_mapping.json` for the complete INFOODS tag → HealthKit field mapping.

Key mappings:
- `enercKcal` → `calories` (already in kcal)
- `prot` → `protein_g`
- `fat` → `fat_g`
- `chocdf` → `carbs_g` (carbohydrates by difference)
- `fib` → `fiber_g`
- `na` → `sodium_mg`
- `vitaRae` → `vitamin_a_mcg` (retinol activity equivalents)
- `tocphA` → `vitamin_e_mg` (alpha-tocopherol)

## Matching Algorithm

The matching uses a combined token-based + sequence similarity approach:
1. Normalize both query and DB names (strip `<category>` prefixes, convert brackets to spaces)
2. Token F1 score (70% weight): measures overlap of word tokens
3. SequenceMatcher ratio (30% weight): catches partial matches
4. Threshold: 0.35 minimum score to accept a match

Claude is prompted to use formal food names (e.g., "こめ 水稲めし 精白米 うるち米" instead of "ご飯") which typically achieve scores of 0.8-1.0.
