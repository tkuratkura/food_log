# iOS Shortcut "FoodLog" - Step-by-Step Build Guide

## Before You Start

### Prerequisites

1. **Mac**: System Settings > General > Sharing > **Remote Login** ON
2. **Mac**: Note your hostname (e.g., `tkura-mac.local` or IP `192.168.1.x`)
3. **Mac**: `~/GIT/food_log/scripts/analyze.sh` exists and is executable
4. **Mac**: Claude Code CLI (`claude`) is installed
5. **iPhone**: iCloud Drive enabled

### SSH Key Setup (Do This First)

Setting up SSH keys avoids entering your password every time.

On your **iPhone**, open Shortcuts and create a temporary shortcut:

1. Add **"Run Script over SSH"** action
2. Host: your Mac hostname, User: your Mac username
3. Script: `cat ~/.ssh/authorized_keys`
4. If this works with password, proceed. If not, enable Remote Login on Mac.

To set up key-based auth, run this on Mac Terminal:
```bash
# If you don't have a key yet
ssh-keygen -t ed25519

# The Shortcuts app stores its own SSH keys.
# On first SSH connection from Shortcuts, it will prompt for password
# and offer to store credentials. Accept this.
```

---

## Build the Shortcut

Open **Shortcuts** app on iPhone. Tap **+** to create new shortcut.

### Part 1: Input Selection (Photo or Text)

---

**Action 1** — `Receive What's On Screen input from Share Sheet`

> Tap "Images" to set accepted types to **Images**.
> This lets you trigger FoodLog from the Photos app share button.

---

**Action 2** — `If`

> Condition: `Shortcut Input` → `has any value`

This checks if a photo was passed from the Share Sheet.

---

**Action 3** (inside If → true branch) — `Set Variable`

> Variable Name: `InputMode`
> Value: `photo`

---

**Action 4** (inside If → true branch) — `Set Variable`

> Variable Name: `MealPhoto`
> Value: `Shortcut Input`

---

**Action 5** — `Otherwise`

(This is the else branch — shortcut was launched directly, not from Share Sheet)

---

**Action 6** (inside Otherwise) — `Choose from Menu`

> Prompt: `記録方法を選択`
> Option 1: `写真を撮る`
> Option 2: `写真を選ぶ`
> Option 3: `テキストで入力`
> Option 4: `テンプレート`

---

**Action 7** (inside 写真を撮る) — `Take Photo`

> (No special config needed)

---

**Action 8** (inside 写真を撮る) — `Set Variable`

> Variable Name: `MealPhoto`, Value: `Photo`

---

**Action 9** (inside 写真を撮る) — `Set Variable`

> Variable Name: `InputMode`, Value: `photo`

---

**Action 10** (inside 写真を選ぶ) — `Select Photos`

> (No special config needed)

---

**Action 11** (inside 写真を選ぶ) — `Set Variable`

> Variable Name: `MealPhoto`, Value: `Photos`

---

**Action 12** (inside 写真を選ぶ) — `Set Variable`

> Variable Name: `InputMode`, Value: `photo`

---

**Action 13** (inside テキストで入力) — `Ask for Input`

> Prompt: `何を食べましたか？ (例: 味噌ラーメンと餃子5個)`
> Input Type: `Text`

---

**Action 14** (inside テキストで入力) — `Set Variable`

> Variable Name: `MealText`, Value: `Provided Input`

---

**Action 15** (inside テキストで入力) — `Set Variable`

> Variable Name: `InputMode`, Value: `text`

---

**Action 15b** (inside テンプレート) — `Run Script over SSH`

> Same Host/Port/User as other SSH actions
> Script:
> ```
> ~/GIT/food_log/scripts/list-templates.sh json
> ```

---

**Action 15c** (inside テンプレート) — `Get Dictionary from Input`

> Input: `Shell Script Result`

---

**Action 15d** (inside テンプレート) — `Repeat with Each`

> Input: `Dictionary` (the JSON array)

Inside Repeat:

> **Get Dictionary Value** — Key: `name`, from: `Repeat Item`
> **Get Dictionary Value** — Key: `calories`, from: `Repeat Item`
> **Text** — `[Name] ([Calories] kcal)`

End Repeat → produces a list of display strings

---

**Action 15e** (inside テンプレート) — `Choose from List`

> Input: `Repeat Results`
> Prompt: `テンプレートを選択`

---

**Action 15f** (inside テンプレート) — `Show Alert`

> Title: `確認`
> Message: `「[Chosen Item]」をヘルスケアに記録しますか？`
> Buttons: `Show Cancel Button` = ON

(Cancel tapped → shortcut stops automatically)

---

**Action 15g** (inside テンプレート) — `Replace Text`

> Find: ` \(.*\)$` (enable Regular Expression)
> Replace with: (empty)
> Input: `Chosen Item`

This extracts just the template name (removes the " (256 kcal)" suffix).

---

**Action 15h** (inside テンプレート) — `Set Variable`

> Variable Name: `MealText`, Value: `Updated Text`

---

**Action 15i** (inside テンプレート) — `Set Variable`

> Variable Name: `InputMode`, Value: `text`

---

**Action 16** — `End Choose from Menu`

---

**Action 17** — `End If`

---

### Part 1.5: Meal Time Picker

---

**Action 18** — `Ask for Input`

> Prompt: `食べた時刻を選んでください`
> Input Type: `Date and Time`
> Default: `Current Date`

The user can adjust the time if they ate earlier (e.g., logging a meal after the fact). If they just ate, they simply tap "Done".

---

**Action 19** — `Format Date`

> Date: `Provided Input` (from Action 18)
> Date Format: `Custom` → `yyyy-MM-dd_HHmmss`

---

**Action 20** — `Set Variable`

> Variable Name: `MealTime`, Value: `Formatted Date`

---

### Part 2: Run Analysis on Mac

---

**Action 21** — `If`

> Condition: `InputMode` → `is` → `photo`

---

**Action 22** (inside If → photo) — `Set Variable`

> Variable Name: `Filename`, Value: `MealTime`

---

**Action 23** (inside If → photo) — `Save File`

> File: `MealPhoto`
> Ask Where to Save: OFF
> Destination Path: `/FoodLog/inbox/` + `Filename` + `.jpg`
>
> (This saves to iCloud Drive > FoodLog > inbox)

---

**Action 24** (inside If → photo) — `Run Script over SSH`

> Host: `your-mac-hostname`
> Port: `22`
> User: `your-mac-username`
> Authentication: Password (first time) or SSH Key
> Script:
> ```
> ~/GIT/food_log/scripts/analyze.sh --time "[MealTime]" "$HOME/Library/Mobile Documents/com~apple~CloudDocs/FoodLog/inbox/[Filename].jpg"
> ```
> **Important**: Insert the `MealTime` variable where `[MealTime]` is shown, and the `Filename` variable where `[Filename]` is shown.

---

**Action 25** — `Otherwise`

(Text input branch)

---

**Action 26** (inside Otherwise) — `Run Script over SSH`

> Same Host/Port/User as Action 24
> Script:
> ```
> ~/GIT/food_log/scripts/analyze.sh --time "[MealTime]" "[MealText]"
> ```
> **Important**: Insert the `MealTime` and `MealText` variables where shown.

---

**Action 27** — `End If`

---

**Action 28** — `Set Variable`

> Variable Name: `SSHResult`, Value: `Shell Script Result`
>
> (Tap "Shell Script Result" — it's the magic variable from whichever SSH action ran)

---

### Part 3: Parse JSON

---

**Action 29** — `Get Dictionary from Input`

> Input: `SSHResult`

---

**Action 30** — `Set Variable`

> Variable Name: `Result`, Value: `Dictionary`

---

**Action 31** — `Get Dictionary Value`

> Get `Value` for `Key`: `totals`
> from: `Result`

---

**Action 32** — `Set Variable`

> Variable Name: `Totals`, Value: `Dictionary Value`

---

**Action 33** — `Get Dictionary Value`

> Get `Value` for `Key`: `meal_description`
> from: `Result`

---

**Action 34** — `Set Variable`

> Variable Name: `Description`, Value: `Dictionary Value`

---

**Action 35** — `Get Dictionary Value`

> Get `Value` for `Key`: `calories`
> from: `Totals`

---

**Action 36** — `Set Variable`

> Variable Name: `CalorieTotal`, Value: `Dictionary Value`

---

**Action 37** — `Get Dictionary Value`

> Get `Value` for `Key`: `meal_id`
> from: `Result`

---

**Action 38** — `Set Variable`

> Variable Name: `MealID`, Value: `Dictionary Value`

---

### Part 3.5: Confirm Before Logging

---

**Action 39** — `Choose from Menu`

> Prompt: `Description` + ` ` + `CalorieTotal` + ` kcal` + newline + `ヘルスケアに記録しますか？`
> Option 1: `記録する`
> Option 2: `キャンセル`

---

**Action 40** (inside キャンセル) — `Run Script over SSH`

> Same Host/Port/User as other SSH actions
> Script:
> ```
> rm -f "$HOME/Library/Mobile Documents/com~apple~CloudDocs/FoodLog/results/[MealID].json"
> ```
> **Important**: Insert the `MealID` variable where `[MealID]` is shown.

---

**Action 41** (inside キャンセル) — `Stop Shortcut`

> (Stops execution — nothing is logged to HealthKit)

---

**Action 42** — `End Choose from Menu`

(Continues below only if 記録する was chosen)

---

### Part 4: Log to HealthKit

Each nutrient needs its own block: **Get value → Check not null → Log**.

Here's the pattern. **Repeat this for each nutrient** in the table below:

```
[Get Dictionary Value] Key: (key), from: Totals
  ↓
[If] Dictionary Value — has any value
  ↓
  [Log Health Sample] Type: (HealthKit type), Value: (Dictionary Value), Unit: (unit)
  ↓
[End If]
```

#### Step-by-step for the first nutrient (Calories):

Since `CalorieTotal` was already extracted in Part 3.5, we can use it directly:

**Action 38** — `If`
> `CalorieTotal` → `has any value`

**Action 39** — `Log Health Sample`
> Type: **Dietary Energy**
> Value: `CalorieTotal`
> Unit: **kcal**

**Action 40** — `End If`

---

#### Repeat the same 4-action pattern for each nutrient:

**Macronutrients** — Do these first (most important):

| # | Key | HealthKit Type | Unit |
|---|-----|---------------|------|
| 1 | `calories` | Dietary Energy | kcal |
| 2 | `protein_g` | Protein | g |
| 3 | `fat_g` | Total Fat | g |
| 4 | `carbs_g` | Carbohydrates | g |
| 5 | `fiber_g` | Fiber | g |
| 6 | `sugar_g` | Dietary Sugar | g |
| 7 | `saturated_fat_g` | Saturated Fat | g |
| 8 | `monounsaturated_fat_g` | Monounsaturated Fat | g |
| 9 | `polyunsaturated_fat_g` | Polyunsaturated Fat | g |
| 10 | `cholesterol_mg` | Dietary Cholesterol | mg |

**Minerals**:

| # | Key | HealthKit Type | Unit |
|---|-----|---------------|------|
| 11 | `sodium_mg` | Sodium | mg |
| 12 | `potassium_mg` | Potassium | mg |
| 13 | `calcium_mg` | Calcium | mg |
| 14 | `iron_mg` | Iron | mg |
| 15 | `magnesium_mg` | Magnesium | mg |
| 16 | `phosphorus_mg` | Phosphorus | mg |
| 17 | `zinc_mg` | Zinc | mg |
| 18 | `copper_mg` | Copper | mg |
| 19 | `manganese_mg` | Manganese | mg |
| 20 | `selenium_mcg` | Selenium | mcg |
| 21 | `chromium_mcg` | Chromium | mcg |
| 22 | `molybdenum_mcg` | Molybdenum | mcg |
| 23 | `iodine_mcg` | Iodine | mcg |
| 24 | `chloride_mg` | Chloride | mg |

**Vitamins**:

| # | Key | HealthKit Type | Unit |
|---|-----|---------------|------|
| 25 | `vitamin_a_mcg` | Vitamin A | mcg |
| 26 | `vitamin_c_mg` | Vitamin C | mg |
| 27 | `vitamin_d_mcg` | Vitamin D | mcg |
| 28 | `vitamin_e_mg` | Vitamin E | mg |
| 29 | `vitamin_k_mcg` | Vitamin K | mcg |
| 30 | `vitamin_b1_mg` | Thiamin | mg |
| 31 | `vitamin_b2_mg` | Riboflavin | mg |
| 32 | `vitamin_b6_mg` | Vitamin B6 | mg |
| 33 | `vitamin_b12_mcg` | Vitamin B12 | mcg |
| 34 | `niacin_mg` | Niacin | mg |
| 35 | `folate_mcg` | Folate | mcg |
| 36 | `pantothenic_acid_mg` | Pantothenic Acid | mg |
| 37 | `biotin_mcg` | Biotin | mcg |

**Other**:

| # | Key | HealthKit Type | Unit |
|---|-----|---------------|------|
| 38 | `caffeine_mg` | Caffeine | mg |
| 39 | `water_ml` | Water | mL |

> **Tip**: Start with #1-10 (macronutrients) to get a working shortcut quickly.
> Add minerals and vitamins later — the shortcut works fine without them.
> You can duplicate the 4-action block (long-press → Duplicate) to speed this up.

---

### Part 5: Log to Reminders & Notification

After all the Log Health Sample blocks:

---

**Action (last-6)** — `Get Dictionary Value`
> Key: `protein_g`, from: `Totals`

**Action (last-5)** — `Get Dictionary Value`
> Key: `fat_g`, from: `Totals`

**Action (last-4)** — `Get Dictionary Value`
> Key: `fiber_g`, from: `Totals`

**Action (last-3)** — `Format Date`
> Date: `MealTime` (from Part 1.5)
> Date Format: `Custom` → `yyyy/MM/dd HH:mm`

---

**Action (last-2)** — `Text`

> ```
> P:[protein_g]g F:[fat_g]g C:[CarbohydrateTotal]g Fiber:[fiber_g]g
> [Formatted Date]
> ```
> Insert the variables from the actions above where `[...]` is shown.
> `CarbohydrateTotal` is the `carbs_g` value — reuse from Part 4's HealthKit logging if already extracted, or add another `Get Dictionary Value` for `carbs_g` here.

---

**Action (last-1)** — `Add New Reminder`

> Reminder: `Description` + ` ` + `CalorieTotal` + ` kcal`
> List: `FoodLog`
> Notes: `Text` (from previous action)
> Alert: `MealTime` (from Part 1.5 date picker)
> Mark as Completed: ON

This creates a completed reminder in the "FoodLog" list with the meal time as the date. The notes contain PFC, fiber, and the recorded time. Browse your meal history anytime in the Reminders app.

> **Setup**: Before first use, create a list named **FoodLog** in the Reminders app on your iPhone.

---

**Action (last-1)** — `Show Notification`

> Title: `FoodLog`
> Body: `Description` + ` ` + `CalorieTotal` + ` kcal`

`CalorieTotal` and `Description` were already set in Part 3/3.5.

---

### Part 6: Name and Configure

1. Tap the shortcut name at the top → rename to **FoodLog**
2. Tap the **ⓘ** button at top:
   - Enable **Show in Share Sheet**
   - Enable **Use as Quick Action**
   - Pin to Home Screen (optional): tap **Add to Home Screen**

---

### Part 4b: Template/Preset Handling

When `InputMode` is `template`, the SSH result from `analyze.sh` may contain multiple base64-encoded lines (one per meal in a preset). The Shortcut must handle this.

---

**Modified flow** (replaces the existing single base64 decode):

**Action T1** — `Split Text`

> Input: `Shell Script Result`
> Separator: `New Lines`

---

**Action T2** — `Repeat with Each`

> Input: `Split Text Result`

---

**Action T3** (inside Repeat) — `Decode`

> Input: `Repeat Item`
> Decode as: `Base64`

---

**Action T4** (inside Repeat) — `Run Shortcut`

> Shortcut: `Foodlog:HealthKit 1`
> Input: `Decoded Result`

---

**Action T5** — `End Repeat`

This works for both single templates (1 line → 1 iteration) and presets (N lines → N iterations). Each line is a complete `{count: 1, meals: [...]}` JSON, identical to single-template output.

---

### Part 7: FoodLog:Delete Shortcut (Separate Shortcut)

A dedicated shortcut for deleting meal records from both iCloud results and HealthKit.

---

**Action D1** — `Choose from Menu`

> Prompt: `削除方法を選択`
> Option 1: `日付で削除`
> Option 2: `プリセットで削除`

---

#### Option 1: 日付で削除

**Action D2** — `Ask for Input`

> Prompt: `日付を選択`
> Input Type: `Date`
> Default: `Current Date`

---

**Action D3** — `Format Date`

> Date Format: `Custom` → `yyyy-MM-dd`

---

**Action D4** — `Run Script over SSH`

> Script: `~/GIT/food_log/scripts/list-meals.sh -d [Formatted Date] json`

---

**Action D5** — `Get Dictionary from Input`

> Input: `Shell Script Result`

---

**Action D6** — `Repeat with Each`

Build display strings: `[meal_id] [description] ([calories] kcal)`

---

**Action D7** — `Choose from List`

> Prompt: `削除する食事を選択`
> Select Multiple: `ON`

---

**Action D8** — Extract `meal_id` from each selected item (Replace Text to remove description suffix)

---

**Action D9** — `Run Script over SSH`

> Script: `~/GIT/food_log/scripts/delete-meal.sh [selected meal_ids]`

---

#### Option 2: プリセットで削除

**Action D10** — `Ask for Input`

> Prompt: `日付を選択`
> Input Type: `Date`
> Default: `Current Date`

---

**Action D11** — `Format Date`

> Date Format: `Custom` → `yyyy-MM-dd`

---

**Action D12** — `Run Script over SSH`

> Script: `~/GIT/food_log/scripts/delete-meal.sh --preset 平日昼間 --date [Formatted Date]`

---

#### HealthKit Cleanup (shared by both options)

**Action D13** — `Get Dictionary from Input`

> Input: `Shell Script Result` (JSON array of timestamps)

---

**Action D14** — `Repeat with Each`

> Input: `Dictionary` (the timestamp array)

---

**Action D15** (inside Repeat) — `Find Health Samples`

> Sample Type: `Dietary Energy` (and other nutrient types)
> Start Date: `Repeat Item` (the timestamp)
> End Date: `Repeat Item`

---

**Action D16** (inside Repeat) — `Delete Health Samples`

> Input: `Health Samples`

---

**Action D17** — `End Repeat`

---

**Action D18** — `Show Notification`

> Title: `FoodLog`
> Body: `削除しました`

---

## How It Looks When Done

```
[Receive input from Share Sheet (Images)]
[If] Shortcut Input has any value
  [Set Variable] InputMode = "photo"
  [Set Variable] MealPhoto = Shortcut Input
[Otherwise]
  [Choose from Menu] 写真を撮る / 写真を選ぶ / テキストで入力 / テンプレート
    [写真を撮る]
      [Take Photo] → MealPhoto, InputMode = "photo"
    [写真を選ぶ]
      [Select Photos] → MealPhoto, InputMode = "photo"
    [テキストで入力]
      [Ask for Input] → MealText, InputMode = "text"
    [テンプレート]
      [SSH] list-templates.sh json → [Parse JSON] → [Repeat: "name (cal kcal)"]
      → [Choose from List] → [Alert: ヘルスケアに記録しますか？] → [Extract name] → MealText, InputMode = "template"
  [End Menu]
[End If]

[Ask for Input] 食べた時刻 (Date and Time, default: now) → MealTime

[If] InputMode is "photo"
  Filename = MealTime
  [Save File] MealPhoto → iCloud Drive/FoodLog/inbox/
  [SSH] analyze.sh --time [MealTime] with photo path
  [Base64 Decode] → [Parse JSON] → confirm → HealthKit × 39 nutrients
[Otherwise if] InputMode is "template"
  [SSH] analyze.sh --time [MealTime] [MealText]
  [Split Text by newlines]
  [Repeat with Each]
    [Base64 Decode] → [Foodlog:HealthKit 1]
  [End Repeat]
[Otherwise]
  [SSH] analyze.sh --time [MealTime] with MealText
  [Base64 Decode] → [Parse JSON] → confirm → HealthKit × 39 nutrients
[End If]

[Show Notification] "FoodLog: 味噌ラーメン 650 kcal"

---

FoodLog:Delete (separate shortcut):
[Choose from Menu] 日付で削除 / プリセットで削除
  [日付で削除]
    [Date Picker] → [SSH] list-meals.sh -d [date] json
    → [Choose from List (multiple)] → [SSH] delete-meal.sh [meal_ids]
  [プリセットで削除]
    [Date Picker] → [SSH] delete-meal.sh --preset 平日昼間 --date [date]
[End Menu]
→ [Parse timestamp JSON] → [Repeat: Find + Delete Health Samples]
→ [Notification] 削除しました
```

---

## Usage

### From Photos App
1. Open meal photo → tap **Share** → tap **FoodLog**
2. Wait ~30-60 seconds
3. Notification: "味噌ラーメンと餃子 850 kcal"

### From Home Screen / Shortcuts App
1. Tap **FoodLog** icon
2. Choose: 写真を撮る / 写真を選ぶ / テキストで入力
3. Wait for analysis
4. Notification confirms logging

### From Action Button (iPhone 15 Pro+)
Settings > Action Button > Shortcut > FoodLog

---

## Troubleshooting

### SSH Connection Fails
- Verify Mac's Remote Login is ON
- Check hostname: on Mac, run `hostname` in Terminal
- Try IP address instead of `.local` hostname
- First-time connection will ask for password — enter it to store credentials

### "Shell Script Result" is Empty
- SSH into Mac manually and test: `~/GIT/food_log/scripts/analyze.sh "テスト おにぎり"`
- Check that `claude` is in PATH for non-interactive shells:
  add to `~/.zshenv` on Mac: `export PATH="$HOME/.claude/bin:$PATH"` (adjust path as needed)

### HealthKit Permission Denied
- First run will prompt for HealthKit access — tap Allow
- If denied: Settings > Health > Data Access & Devices > Shortcuts > Enable all

### Analysis Takes Too Long
- Normal time: 30-60 seconds
- Make sure Mac is awake (not sleeping)
- Check Mac's network connection

### Dictionary Value Errors
- If JSON parsing fails, the SSH output may contain non-JSON text
- Test the script directly: `~/GIT/food_log/scripts/analyze.sh "おにぎり"` — output should be pure JSON
