#!/usr/bin/env python3
"""Replace Claude's nutrient estimates with values from the Japanese Standard
Tables of Food Composition (日本食品標準成分表 八訂) where a match is found.

Usage:
    python3 lookup-nutrients.py <meal_json_path>

Modifies the JSON file in-place, adding nutrient_source and food_db_id fields.
"""

import json
import re
import sys
import os
from difflib import SequenceMatcher

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
FOOD_DB_PATH = os.path.join(SCRIPT_DIR, "..", "data", "food_db", "standard_tables.json")
FIELD_MAPPING_PATH = os.path.join(SCRIPT_DIR, "..", "data", "food_db", "field_mapping.json")

# Minimum similarity score to accept a DB match (0.0 - 1.0)
MATCH_THRESHOLD = 0.35


def load_food_db():
    with open(FOOD_DB_PATH, encoding="utf-8") as f:
        return json.load(f)


def load_field_mapping():
    with open(FIELD_MAPPING_PATH, encoding="utf-8") as f:
        data = json.load(f)
    return data["mapping"], data["not_in_db"]


def normalize_name(name):
    """Lightly clean food name for matching. Keep bracket content since it
    distinguishes e.g. [水稲めし] (cooked) from [水稲穀粒] (raw grain)."""
    # Remove only angle-bracket category prefixes like <畜肉類>
    name = re.sub(r"<[^>]+>", "", name)
    # Convert brackets to spaces so content is preserved for matching
    name = name.replace("[", " ").replace("]", " ")
    name = name.replace("(", " ").replace(")", " ")
    # Collapse whitespace
    name = re.sub(r"\s+", " ", name).strip()
    return name


def score_match(query, db_name):
    """Score how well a query matches a DB food name. Higher is better."""
    norm_db = normalize_name(db_name)
    norm_query = normalize_name(query)

    # Exact match
    if norm_query == norm_db:
        return 1.0

    # Token-based scoring: split both into tokens and measure overlap
    query_tokens = set(re.split(r"[\s　·･]+", norm_query))
    query_tokens.discard("")
    db_tokens = set(re.split(r"[\s　·･]+", norm_db))
    db_tokens.discard("")

    if not query_tokens:
        return 0.0

    # Count how many query tokens appear in the DB name string
    hits = sum(1 for t in query_tokens if t in norm_db)
    token_recall = hits / len(query_tokens)

    # Penalize if DB name has many extra tokens (prefer specific matches)
    precision = hits / max(len(db_tokens), 1)

    # F1-like score combining recall and precision
    if token_recall + precision > 0:
        token_f1 = 2 * token_recall * precision / (token_recall + precision)
    else:
        token_f1 = 0.0

    # SequenceMatcher as secondary signal
    seq_score = SequenceMatcher(None, norm_query, norm_db).ratio()

    # Weighted combination: tokens more important than sequence similarity
    return 0.7 * token_f1 + 0.3 * seq_score


def find_best_match(query, food_db):
    """Find the best matching food in the DB for the given query."""
    best_score = 0
    best_item = None
    for item in food_db:
        s = score_match(query, item["foodName"])
        if s > best_score:
            best_score = s
            best_item = item
    return best_item, best_score


def calculate_nutrients(db_item, portion_g, field_mapping):
    """Calculate nutrients for a given portion size using DB values (per 100g)."""
    ratio = portion_g / 100.0
    nutrients = {}
    for db_field, info in field_mapping.items():
        target = info["target"]
        db_val = db_item.get(db_field)
        if db_val is None:
            nutrients[target] = None
        else:
            val = db_val * ratio
            # Round appropriately: integers for kcal/mg-level, 1 decimal for g-level
            if info["unit"] in ("kcal",):
                nutrients[target] = round(val)
            elif info["unit"] in ("mg", "mcg"):
                nutrients[target] = round(val, 1)
            else:
                nutrients[target] = round(val, 1)
    return nutrients


def process_meal(meal_path):
    with open(meal_path, encoding="utf-8") as f:
        meal = json.load(f)

    food_db = load_food_db()
    field_mapping, not_in_db = load_field_mapping()

    for item in meal.get("food_items", []):
        # Skip items with nutrients sourced from a nutrition label (OCR)
        if item.get("nutrient_source") == "label":
            continue

        query = item.get("food_db_search", "")
        portion_g = item.get("portion_g")

        if not query or not portion_g:
            item["nutrient_source"] = "estimated"
            continue

        best, score = find_best_match(query, food_db)

        if best and score >= MATCH_THRESHOLD:
            db_nutrients = calculate_nutrients(best, portion_g, field_mapping)
            # Replace nutrient values with DB values (keep Claude estimates for not_in_db fields)
            for target_field, db_val in db_nutrients.items():
                item[target_field] = db_val

            item["nutrient_source"] = "food_db"
            item["food_db_id"] = best["foodId"]
            item["food_db_name"] = best["foodName"]
            item["food_db_score"] = round(score, 3)
        else:
            item["nutrient_source"] = "estimated"
            if best:
                item["food_db_nearest"] = best["foodName"]
                item["food_db_score"] = round(score, 3)

    # Recalculate totals
    recalculate_totals(meal)

    with open(meal_path, "w", encoding="utf-8") as f:
        json.dump(meal, f, ensure_ascii=False, indent=2)


def recalculate_totals(meal):
    """Sum nutrient values across all food_items. null excluded; all-null stays null."""
    nutrient_fields = [
        "calories", "protein_g", "fat_g", "carbs_g", "fiber_g", "sugar_g",
        "saturated_fat_g", "monounsaturated_fat_g", "polyunsaturated_fat_g",
        "cholesterol_mg", "sodium_mg", "potassium_mg", "calcium_mg", "iron_mg",
        "magnesium_mg", "phosphorus_mg", "zinc_mg", "copper_mg", "manganese_mg",
        "selenium_mcg", "chromium_mcg", "molybdenum_mcg", "iodine_mcg",
        "chloride_mg", "vitamin_a_mcg", "vitamin_c_mg", "vitamin_d_mcg",
        "vitamin_e_mg", "vitamin_k_mcg", "vitamin_b1_mg", "vitamin_b2_mg",
        "vitamin_b6_mg", "vitamin_b12_mcg", "niacin_mg", "folate_mcg",
        "pantothenic_acid_mg", "biotin_mcg", "caffeine_mg", "water_ml"
    ]

    totals = {}
    items = meal.get("food_items", [])
    for field in nutrient_fields:
        values = [item.get(field) for item in items]
        non_null = [v for v in values if v is not None]
        if non_null:
            total = sum(non_null)
            if isinstance(total, float):
                totals[field] = round(total, 1)
            else:
                totals[field] = total
        else:
            totals[field] = None
    meal["totals"] = totals


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <meal_json_path>", file=sys.stderr)
        sys.exit(1)

    meal_path = sys.argv[1]
    if not os.path.exists(meal_path):
        print(f"File not found: {meal_path}", file=sys.stderr)
        sys.exit(1)

    process_meal(meal_path)
