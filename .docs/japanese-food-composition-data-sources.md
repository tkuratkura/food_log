# Japanese Food Composition Data Sources

Research on obtaining the Japanese Standard Tables of Food Composition (日本食品標準成分表 八訂) in machine-readable formats.

## 1. Official MEXT Data (Excel Format)

**Source:** Ministry of Education, Culture, Sports, Science and Technology (文部科学省)

### Main Download Page
- **八訂 増補2023年版:** https://www.mext.go.jp/a_menu/syokuhinseibun/mext_00001.html
- **八訂 2020年版 (original):** https://www.mext.go.jp/a_menu/syokuhinseibun/mext_01110.html

### Direct Excel Downloads (増補2023年)
| File | URL |
|------|-----|
| Main composition table (本表) | `https://www.mext.go.jp/content/20230428-mxt_kagsei-mext_00001_012.xlsx` |
| Amino acid table 1 | `https://www.mext.go.jp/content/20230428-mxt_kagsei-mext_00001_022.xlsx` |
| Amino acid table 2 | `https://www.mext.go.jp/content/20230428-mxt_kagsei-mext_00001_023.xlsx` |
| Amino acid table 3 | `https://www.mext.go.jp/content/20230428-mxt_kagsei-mext_00001_024.xlsx` |
| Amino acid table 4 | `https://www.mext.go.jp/content/20230428-mxt_kagsei-mext_00001_025.xlsx` |
| Fatty acid table 1 | `https://www.mext.go.jp/content/20230428-mxt_kagsei-mext_00001_032.xlsx` |
| Fatty acid table 2 | `https://www.mext.go.jp/content/20230428-mxt_kagsei-mext_00001_033.xlsx` |
| Fatty acid table 3 | `https://www.mext.go.jp/content/20230428-mxt_kagsei-mext_00001_034.xlsx` |
| Carbohydrate table | `https://www.mext.go.jp/content/20230428-mxt_kagsei-mext_00001_042.xlsx` |

### Caveats
- Excel files contain merged cells, line breaks, and full-width characters
- Requires preprocessing to be machine-readable
- 2,478 food items in the 2020 (8th) edition

## 2. MEXT Food Composition Database (Web Interface)

- **URL:** https://fooddb.mext.go.jp/
- **Data source:** 八訂 増補2023年
- **Features:** Free-word search, food name list search, nutrient ranking
- **API:** No public API available. Web-only interface.
- Scraping would be required for programmatic access (check terms of service)

## 3. GitHub: JSON Conversion (Best for Integration)

### katoharu432/standards-tables-of-food-composition-in-japan
- **URL:** https://github.com/katoharu432/standards-tables-of-food-composition-in-japan
- **Format:** JSON (`data.json`), also CSV in `/csv` directory
- **License:** CC BY 4.0
- **Data:** 八訂 2020年版 (note: does NOT include 増補2023 additions)
- **Structure:** camelCase keys based on FAO/INFOODS tagnames
- **Fields:** 60+ nutrient fields per food item

#### JSON Example
```json
{
  "groupId": 1,
  "foodId": 1001,
  "foodName": "アマランサス 玄穀",
  "enerc": 1452,
  "water": 13.5,
  "prot": 12.7,
  "fat": 6.0,
  ...
}
```

#### Available Nutrients
- Energy (kcal, kJ)
- Macronutrients (protein, fat, carbohydrates, fiber)
- Minerals (Ca, Fe, Zn, Na, K, Mg, P, Cu, Mn, Se, Cr, Mo, I)
- Vitamins (A, D, E, K, B1, B2, B6, B12, C, niacin, folate, pantothenic acid, biotin)
- Cholesterol, fatty acid fractions, alcohol, caffeine, water

## 4. Dietary Reference Intakes (Complementary Data)

### Biscuit01/Dietary-Reference-Intakes-for-Japanese-2020-csv
- **URL:** https://github.com/Biscuit01/Dietary-Reference-Intakes-for-Japanese-2020-csv
- **Content:** Recommended daily intake values by age group
- **Format:** CSV, organized by age group and by nutrient type
- **Note:** Does not include pregnant/nursing women data; no license specified

## 5. Commercial / Third-Party APIs

### Open Food Facts
- **URL:** https://world.openfoodfacts.org/data
- **Japan instance:** https://jp.openfoodfacts.org/data
- **License:** Open Database License
- **Coverage:** 4M+ products globally, but focuses on packaged foods (barcoded products)
- **Limitation:** Not suitable for traditional Japanese dishes or raw ingredients
- **API:** REST API v2 available, free

### FatSecret Platform API
- **URL:** https://platform.fatsecret.com/
- **Japan support:** Yes (among 56 countries, 24 languages)
- **Coverage:** 2.3M+ unique foods globally
- **Limitation:** Japanese localization requires Premier account
- **API:** REST API, free tier available (rate-limited)

### Edamam
- **URL:** https://developer.edamam.com/
- **Coverage:** 900K+ foods
- **Limitation:** Japanese food coverage unclear
- **API:** REST API, free tier with limits

## Recommendations for Food Log Integration

### Best Approach: Hybrid Strategy

1. **Primary data source:** Use the `katoharu432` JSON repository for a local food composition database. It provides CC BY 4.0 licensed data covering 2,478 Japanese foods with 60+ nutrients per item.

2. **For template/lookup features:** Convert the JSON data into a local SQLite or flat JSON lookup that maps Japanese food names to nutritional profiles.

3. **For Claude analysis validation:** Use the MEXT composition data as a reference to cross-check Claude's nutritional estimates.

4. **For packaged foods:** Supplement with Open Food Facts API (barcode scanning).

### Steps to Integrate
1. Clone or download `data.json` from the katoharu432 repo
2. Map FAO/INFOODS tagnames to your HealthKit-compatible field names
3. Build a name-matching index (fuzzy search on `foodName`)
4. Use as a lookup table in `analyze.sh` or a new validation script

### Field Mapping (FAO/INFOODS to HealthKit)
Key mappings needed:
- `enerc` (kJ) / `enerc_kcal` -> calories
- `prot` -> protein_g
- `fat` -> fat_g
- `chocdf` -> carbs_g
- `fibtg` -> fiber_g
- `na` -> sodium_mg
- `k` -> potassium_mg
- `ca` -> calcium_mg
- `fe` -> iron_mg
- (see full tagname correspondence table in the repository)
