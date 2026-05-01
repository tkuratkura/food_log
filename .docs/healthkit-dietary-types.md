# Apple HealthKit Dietary/Nutrition Data Types

## Overview

Apple HealthKit provides 40 dietary/nutrition `HKQuantityTypeIdentifier` values for tracking food and nutrient intake. All of these are available in the iOS Shortcuts "Log Health Sample" (Japanese: "ヘルスケアサンプルを記録") action under the "Nutrition" category.

## Complete List of Dietary HKQuantityTypeIdentifier Types

### Macronutrients & Energy

| # | HKQuantityTypeIdentifier | Shortcuts Display Name | Tracks | Unit |
|---|--------------------------|----------------------|--------|------|
| 1 | `dietaryEnergyConsumed` | Dietary Energy | Total caloric energy consumed | kcal (kilocalories) |
| 2 | `dietaryProtein` | Protein | Protein intake | g (grams) |
| 3 | `dietaryCarbohydrates` | Carbohydrates | Total carbohydrate intake | g |
| 4 | `dietaryFiber` | Fiber | Dietary fiber intake | g |
| 5 | `dietarySugar` | Dietary Sugar | Sugar intake | g |
| 6 | `dietaryFatTotal` | Total Fat | Total fat intake | g |
| 7 | `dietaryFatSaturated` | Saturated Fat | Saturated fat intake | g |
| 8 | `dietaryFatMonounsaturated` | Monounsaturated Fat | Monounsaturated fat intake | g |
| 9 | `dietaryFatPolyunsaturated` | Polyunsaturated Fat | Polyunsaturated fat intake | g |
| 10 | `dietaryCholesterol` | Dietary Cholesterol | Cholesterol intake | mg (milligrams) |

### Vitamins

| # | HKQuantityTypeIdentifier | Shortcuts Display Name | Tracks | Unit |
|---|--------------------------|----------------------|--------|------|
| 11 | `dietaryVitaminA` | Vitamin A | Vitamin A (retinol) intake | mcg (micrograms) |
| 12 | `dietaryVitaminB6` | Vitamin B6 | Vitamin B6 (pyridoxine) intake | mg |
| 13 | `dietaryVitaminB12` | Vitamin B12 | Vitamin B12 (cyanocobalamin) intake | mcg |
| 14 | `dietaryVitaminC` | Vitamin C | Vitamin C (ascorbic acid) intake | mg |
| 15 | `dietaryVitaminD` | Vitamin D | Vitamin D intake | mcg |
| 16 | `dietaryVitaminE` | Vitamin E | Vitamin E (alpha-tocopherol) intake | mg |
| 17 | `dietaryVitaminK` | Vitamin K | Vitamin K intake | mcg |
| 18 | `dietaryThiamin` | Thiamin | Vitamin B1 (thiamin) intake | mg |
| 19 | `dietaryRiboflavin` | Riboflavin | Vitamin B2 (riboflavin) intake | mg |
| 20 | `dietaryNiacin` | Niacin | Vitamin B3 (niacin) intake | mg |
| 21 | `dietaryPantothenicAcid` | Pantothenic Acid | Vitamin B5 (pantothenic acid) intake | mg |
| 22 | `dietaryBiotin` | Biotin | Vitamin B7 (biotin) intake | mcg |
| 23 | `dietaryFolate` | Folate | Vitamin B9 (folate/folic acid) intake | mcg |

### Minerals

| # | HKQuantityTypeIdentifier | Shortcuts Display Name | Tracks | Unit |
|---|--------------------------|----------------------|--------|------|
| 24 | `dietaryCalcium` | Calcium | Calcium intake | mg |
| 25 | `dietaryIron` | Iron | Iron intake | mg |
| 26 | `dietaryMagnesium` | Magnesium | Magnesium intake | mg |
| 27 | `dietaryPhosphorus` | Phosphorus | Phosphorus intake | mg |
| 28 | `dietaryPotassium` | Potassium | Potassium intake | mg |
| 29 | `dietarySodium` | Sodium | Sodium intake | mg |
| 30 | `dietaryZinc` | Zinc | Zinc intake | mg |

### Trace Elements

| # | HKQuantityTypeIdentifier | Shortcuts Display Name | Tracks | Unit |
|---|--------------------------|----------------------|--------|------|
| 31 | `dietaryChromium` | Chromium | Chromium intake | mcg |
| 32 | `dietaryCopper` | Copper | Copper intake | mg |
| 33 | `dietaryIodine` | Iodine | Iodine intake | mcg |
| 34 | `dietaryManganese` | Manganese | Manganese intake | mg |
| 35 | `dietaryMolybdenum` | Molybdenum | Molybdenum intake | mcg |
| 36 | `dietarySelenium` | Selenium | Selenium intake | mcg |
| 37 | `dietaryChloride` | Chloride | Chloride intake | mg |

### Other

| # | HKQuantityTypeIdentifier | Shortcuts Display Name | Tracks | Unit |
|---|--------------------------|----------------------|--------|------|
| 38 | `dietaryWater` | Water | Water consumption | mL (milliliters) |
| 39 | `dietaryCaffeine` | Caffeine | Caffeine intake | mg |

### Related (Non-dietary but nutrition-adjacent)

| HKQuantityTypeIdentifier | Tracks | Notes |
|--------------------------|--------|-------|
| `numberOfAlcoholicBeverages` | Number of alcoholic drinks consumed | NOT under dietary prefix; may not be available in Log Health Sample |

## iOS Shortcuts "Log Health Sample" Notes

### Availability

All 39 dietary types listed above are available in the iOS Shortcuts "Log Health Sample" action. When you tap the "Type" field, you can search or browse under the "Nutrition" category to find them.

### Limitations

- The "Type" field does NOT accept variables (you cannot dynamically set the nutrition type from a variable)
- When set to "Ask Each Time", you must search through ALL health data types (not just nutrition)
- Each nutrient requires its own separate "Log Health Sample" action in the shortcut
- `numberOfAlcoholicBeverages` is NOT classified under dietary/nutrition identifiers

### Unit Handling

- HealthKit stores values in canonical units internally
- The Shortcuts action automatically handles unit conversion based on device locale
- You can specify the unit when logging (e.g., kcal, g, mg)

## Relevance to food_log Project

The current food_log project logs these 4 types to HealthKit:

| HealthKit Type | HKQuantityTypeIdentifier | JSON Field |
|---------------|--------------------------|------------|
| Dietary Energy | `dietaryEnergyConsumed` | `total_calories` |
| Protein | `dietaryProtein` | `total_protein_g` |
| Total Fat | `dietaryFatTotal` | `total_fat_g` |
| Carbohydrates | `dietaryCarbohydrates` | `total_carbs_g` |

### Potential Expansion

Additional types that could be added to the analysis JSON and logged via Shortcuts:

- `dietaryFiber` - Fiber (g)
- `dietarySugar` - Sugar (g)
- `dietarySodium` - Sodium (mg)
- `dietaryFatSaturated` - Saturated Fat (g)
- `dietaryCholesterol` - Cholesterol (mg)

## Sources

- [Apple Developer: HKQuantityTypeIdentifier](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier)
- [Apple Developer: Nutrition Type Identifiers](https://developer.apple.com/documentation/healthkit/nutrition-type-identifiers)
- [Microsoft Learn: HKQuantityTypeIdentifier Enum](https://learn.microsoft.com/en-us/dotnet/api/healthkit.hkquantitytypeidentifier)
- [HealthKit Overview (mvolkmann)](https://mvolkmann.github.io/blog/swift/HealthKit/)
