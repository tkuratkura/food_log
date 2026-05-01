#!/usr/bin/env python3
"""Probe Z.AI GLM vision model on food images to evaluate accuracy.

Sends each image through the Z.AI chat completions endpoint (OpenAI-compatible)
and saves the structured JSON response to data/test_results/.

Usage:
  scripts/test_vision.py                       # all jpg in iCloud inbox
  scripts/test_vision.py path/to/img.jpg ...   # explicit list

Requires ZAI_API_KEY in .env or environment.
"""

from __future__ import annotations

import base64
import io
import json
import os
import sys
import time
from pathlib import Path

from PIL import Image
from openai import OpenAI

PROJECT = Path(__file__).resolve().parent.parent
ENV_FILE = PROJECT / ".env"
INBOX = Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/FoodLog/inbox"
OUT_DIR = PROJECT / "data/test_results"

# Z.AI endpoint (OpenAI-compatible)
BASE_URL = "https://api.z.ai/api/paas/v4"
MODEL = os.environ.get("ZAI_MODEL", "glm-5v-turbo")

# Resize long edge to bound input token cost while keeping legibility
MAX_LONG_EDGE = 1568

PROMPT = """You are an expert nutritionist. Analyze this meal photo.

STEP 1 — TEXT READING (do this first if any text is visible):
Transcribe ALL visible packaging/label text exactly as printed (product name, weight,
nutrition facts 栄養成分表示, etc). Output the transcription before analysis.
If no text is visible, skip this step.

STEP 2 — FOOD IDENTIFICATION:
Identify all food items by visually analyzing the image.

STEP 3 — NUTRITIONAL ANALYSIS:
For each food item provide: Japanese name, English name, portion in grams (portion_g),
estimation_notes (reasoning), confidence (high|medium|low), and a full nutrient profile.

If a nutrition label was readable in Step 1, set nutrient_source="label" and use the
label values verbatim (convert 食塩相当量 g × 393.4 = sodium_mg).
Otherwise set nutrient_source="estimated".

For each food, provide food_db_search: the formal name as it appears in
日本食品標準成分表 (八訂), e.g. "こめ 水稲めし 精白米 うるち米". For composite dishes
(curry, ramen, stir-fry), set food_db_search to null.

Return ONLY a JSON object with this structure (no prose, no markdown fences):
{
  "label_text": "transcribed text or null",
  "meal_description": "Japanese description",
  "food_items": [
    {
      "name": "JP", "name_en": "EN", "quantity": "portion desc",
      "portion_g": 0, "food_db_search": "formal name or null",
      "estimation_notes": "reasoning", "confidence": "high|medium|low",
      "nutrient_source": "label|estimated",
      "calories": 0, "protein_g": 0, "fat_g": 0, "carbs_g": 0, "fiber_g": 0,
      "sugar_g": 0, "saturated_fat_g": 0, "monounsaturated_fat_g": 0,
      "polyunsaturated_fat_g": 0, "cholesterol_mg": 0,
      "sodium_mg": 0, "potassium_mg": 0, "calcium_mg": 0, "iron_mg": 0,
      "magnesium_mg": 0, "phosphorus_mg": 0, "zinc_mg": 0,
      "vitamin_a_mcg": 0, "vitamin_c_mg": 0, "vitamin_d_mcg": 0,
      "vitamin_b1_mg": 0, "vitamin_b2_mg": 0, "vitamin_b6_mg": 0,
      "vitamin_b12_mcg": 0, "niacin_mg": 0, "folate_mcg": 0,
      "caffeine_mg": 0, "water_ml": 0
    }
  ]
}
Use null for any nutrient that cannot be reasonably estimated."""


def load_env() -> None:
    if not ENV_FILE.exists():
        return
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip())


def encode_image(path: Path) -> str:
    img = Image.open(path)
    img = img.convert("RGB")
    w, h = img.size
    if max(w, h) > MAX_LONG_EDGE:
        if w >= h:
            img = img.resize((MAX_LONG_EDGE, int(h * MAX_LONG_EDGE / w)))
        else:
            img = img.resize((int(w * MAX_LONG_EDGE / h), MAX_LONG_EDGE))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=85)
    return base64.b64encode(buf.getvalue()).decode()


def analyze(client: OpenAI, image_path: Path) -> dict:
    b64 = encode_image(image_path)
    t0 = time.time()
    resp = client.chat.completions.create(
        model=MODEL,
        max_tokens=4096,
        response_format={"type": "json_object"},
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/jpeg;base64,{b64}"},
                    },
                    {"type": "text", "text": PROMPT},
                ],
            }
        ],
    )
    duration = time.time() - t0
    raw = resp.choices[0].message.content or ""
    try:
        parsed = json.loads(raw)
        parse_error = None
    except json.JSONDecodeError as e:
        parsed = None
        parse_error = str(e)
    return {
        "model": MODEL,
        "image": str(image_path),
        "duration_s": round(duration, 2),
        "usage": resp.usage.model_dump() if resp.usage else None,
        "parse_error": parse_error,
        "raw_response": raw if parsed is None else None,
        "parsed": parsed,
    }


def summarize(result: dict) -> str:
    name = Path(result["image"]).name
    dur = result["duration_s"]
    usage = result.get("usage") or {}
    in_tok = usage.get("prompt_tokens", "?")
    out_tok = usage.get("completion_tokens", "?")
    if result["parse_error"]:
        return f"  {name}: PARSE FAIL ({dur}s, in={in_tok} out={out_tok})"
    p = result["parsed"] or {}
    items = p.get("food_items", [])
    desc = p.get("meal_description", "?")
    has_label = any(f.get("nutrient_source") == "label" for f in items)
    label_tag = " [LABEL]" if has_label else ""
    return f"  {name}: {len(items)} items, {dur}s, in={in_tok} out={out_tok}{label_tag} — {desc}"


def main() -> int:
    load_env()
    if not os.environ.get("ZAI_API_KEY"):
        print("ERROR: ZAI_API_KEY not set in .env or environment", file=sys.stderr)
        return 1

    if len(sys.argv) > 1:
        images = [Path(p) for p in sys.argv[1:]]
    else:
        images = sorted(INBOX.glob("*.jpg"))

    if not images:
        print("No images found", file=sys.stderr)
        return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    client = OpenAI(api_key=os.environ["ZAI_API_KEY"], base_url=BASE_URL)

    print(f"Model: {MODEL}")
    print(f"Images: {len(images)}\n")

    for img_path in images:
        if not img_path.exists():
            print(f"  {img_path.name}: MISSING")
            continue
        try:
            result = analyze(client, img_path)
        except Exception as e:
            print(f"  {img_path.name}: REQUEST FAIL — {type(e).__name__}: {e}")
            continue
        out_file = OUT_DIR / f"{img_path.stem}.{MODEL}.json"
        out_file.write_text(json.dumps(result, ensure_ascii=False, indent=2))
        print(summarize(result))

    print(f"\nResults saved to {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
