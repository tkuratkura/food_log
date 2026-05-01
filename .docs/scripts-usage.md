# スクリプト使い方ガイド

## 概要

`scripts/` ディレクトリには、食事分析・テンプレート管理・デバッグ用のシェルスクリプトが含まれています。

| Script | Purpose |
|--------|---------|
| `analyze.sh` | Main script: analyze meals from image, text, template, or preset |
| `batch-log.sh` | CLI tool for batch-logging presets with date selection and management |
| `delete-meal.sh` | Delete meal result files (by meal_id, date, or preset) |
| `list-meals.sh` | List meal logs with search and filter |
| `list-templates.sh` | List saved templates and presets |
| `save-template.sh` | Save an existing meal log as a reusable template |
| `test-analyze.sh` | Debug script to verify Claude CLI works |
| `reset-reminders.sh` | Mark all FoodLog reminders as completed (runs daily at 5am) |
| `test-ssh.sh` | Debug script to test SSH from iOS Shortcut |

---

## analyze.sh

食事を分析し、39種類のHealthKit対応栄養素を含むJSONを出力するメインスクリプト。6つの入力モードに対応。

### 使い方

```bash
# 1. 画像分析（写真ファイルのパスを指定）
./scripts/analyze.sh /path/to/photo.jpg

# 2. 画像＋補足情報（量や容器サイズなどの追加コンテキスト）
./scripts/analyze.sh /path/to/photo.jpg "100ml小鉢"

# 3. テキスト分析（日本語または英語で食事を記述）
./scripts/analyze.sh "味噌ラーメンと餃子5個"

# 4. テンプレート（Claude分析なし、保存済みデータで即記録）
./scripts/analyze.sh @炒り大豆おやつ

# 5. プリセット（複数テンプレートを一括記録、固定ルーティン向け）
./scripts/analyze.sh @平日昼間

# 6. カスタム時刻（食べた時刻を指定、他の入力モードと組み合わせ可能）
./scripts/analyze.sh --time "2026-03-16_120000" "カレーライス"
./scripts/analyze.sh --time "2026-03-16_120000" @炒り大豆おやつ
./scripts/analyze.sh --time "2026-04-05_000000" @平日昼間   # 昨日分のプリセット

# 6. 引数なし（iCloud inboxの最新写真を自動検出）
./scripts/analyze.sh

# 7. 標準入力（パイプでテキストを渡す）
echo "味噌汁(わかめ)" | ./scripts/analyze.sh
```

### 入力モード一覧

| モード | トリガー | Claude分析 |
|--------|---------|-----------|
| 画像 | `.jpg/.jpeg/.png/.heic` ファイルパス | あり |
| 画像＋補足 | ファイルパス＋追加テキスト引数 | あり |
| テキスト | ファイルパスでない文字列引数 | あり |
| テンプレート | `@`/`＠` 付きまたはテンプレート名に完全一致 | なし（保存済みデータ使用） |
| プリセット | `@プリセット名`（`data/presets/` に定義あり） | なし（複数テンプレートを一括記録） |
| 自動検出 | 引数なし・stdin がTTY | あり（iCloud inboxの最新写真） |
| 標準入力 | パイプでテキストを渡す | あり |

### オプション

| オプション | 説明 | 例 |
|-----------|------|-----|
| `--time` | タイムスタンプを指定（`YYYY-MM-DD_HHMMSS`形式） | `--time "2026-03-16_120000"` |

`--time` は全入力モードと組み合わせ可能。未指定の場合は現在時刻を使用。

### 関連ディレクトリ

| パス | 用途 |
|------|------|
| `~/Library/Mobile Documents/com~apple~CloudDocs/FoodLog/inbox/` | iCloud受信箱（iOS Shortcutから写真が入る） |
| `~/Library/Mobile Documents/com~apple~CloudDocs/FoodLog/results/` | 食事ログJSON保存先（iOS Shortcutも読み取る） |
| `data/templates/` | テンプレートJSON保存先 |
| `data/presets/` | プリセット定義JSON保存先 |

### 出力

- iCloud `FoodLog/results/YYYY-MM-DD_HHMMSS.json` にJSONを保存
- 標準出力にJSONを出力（SSH経由でiOS Shortcutがキャプチャ）

### 環境設定

- プロジェクトルートの `.env` ファイルからOAuthトークンを読み込み（非対話SSH認証用）
- `~/.local/bin` をPATHに追加（`claude` CLIアクセス用）

---

## list-meals.sh

食事ログの一覧表示。検索・日付フィルタ・件数制限に対応。iOS Shortcutの履歴表示機能でも使用。

### 使い方

```bash
# 全件表示（新しい順）
./scripts/list-meals.sh

# 最新10件
./scripts/list-meals.sh -n 10

# キーワード検索
./scripts/list-meals.sh -s ラーメン

# 日付フィルタ
./scripts/list-meals.sh -d 2026-03-16

# JSON出力（iOS Shortcut連携用）
./scripts/list-meals.sh json -n 20
```

### オプション

| オプション | 説明 |
|-----------|------|
| `-n COUNT` | 最新 COUNT 件のみ表示 |
| `-s SEARCH` | 説明・食品名でフィルタ |
| `-d DATE` | 日付でフィルタ（例: `2026-03-16`） |
| `json` | JSON配列で出力（meal_id, calories, protein_g, fat_g, carbs_g, description, items, timestamp） |

---

## save-template.sh

既存の食事ログを再利用可能なテンプレートとして保存する。よく食べるメニューを登録しておくと、Claude分析なしで即座にログ記録できる。

### 使い方

```bash
./scripts/save-template.sh <meal_id> <テンプレート名>

# 例
./scripts/save-template.sh 2026-03-10_094545 "炒り大豆おやつ"
```

### 引数

| 引数 | 説明 | 例 |
|------|------|-----|
| `meal_id` | iCloud `FoodLog/results/` 内のファイル名（`.json` なし） | `2026-03-10_094545` |
| テンプレート名 | テンプレートの名前（`@` 接頭辞で使用） | `炒り大豆おやつ` |

### 動作内容

1. iCloud `FoodLog/results/<meal_id>.json` から食事ログを読み込む
2. `food_items`、`totals`、`meal_description` を抽出
3. `data/templates/<テンプレート名>.json` として保存

### テンプレートの使用

保存後は `analyze.sh` で `@` 接頭辞を付けて使用：

```bash
./scripts/analyze.sh @炒り大豆おやつ
```

引数なしで実行すると、既存テンプレートの一覧を表示する。

---

## list-templates.sh

List saved templates and presets. Used by iOS Shortcut to build the template selection menu.

### 使い方

```bash
# Human-readable table
./scripts/list-templates.sh

# JSON array (for iOS Shortcut)
./scripts/list-templates.sh json

# Names only (newline-separated)
./scripts/list-templates.sh names
```

### Output format

| Option | Format |
|--------|--------|
| (none) | Table: templates with kcal/items, presets with meal count |
| `json` | JSON array with `{name, description, calories, type}` — type is `"template"` or `"preset"` (presets also include `meal_count`) |
| `names` | Template and preset names, one per line |

---

## batch-log.sh

CLI tool for batch-logging presets. Provides date selection, listing, and preview that `analyze.sh` does not offer. Primarily for terminal use (iOS uses `analyze.sh @preset` instead).

### 使い方

```bash
# Log preset for today
./scripts/batch-log.sh 平日昼間

# Log preset for a specific date
./scripts/batch-log.sh 平日昼間 2026-04-05

# List available presets
./scripts/batch-log.sh --list

# Show preset contents
./scripts/batch-log.sh --show 平日昼間
```

### Preset definition format

Presets are stored in `data/presets/<name>.json`:

```json
{
  "preset_name": "平日昼間",
  "description": "Weekday daytime meals (fixed routine)",
  "meals": [
    { "template": "お酢ドリンク", "time": "07:30" },
    { "template": "スーパー大麦", "time": "07:30" },
    { "template": "大豆の間食", "time": "09:30" }
  ]
}
```

- `template`: must match a file in `data/templates/`
- `time`: `HH:MM` format, used as the meal timestamp
- Duplicate times get second-offset for unique timestamps (e.g., `_073000`, `_073001`)

---

## delete-meal.sh

Delete meal result files from iCloud Drive. Returns deleted timestamps as JSON array for iOS Shortcut to clean up HealthKit entries.

### 使い方

```bash
# Delete a single meal
./scripts/delete-meal.sh 2026-04-06_073000

# Delete multiple meals
./scripts/delete-meal.sh 2026-04-06_073000 2026-04-06_073001

# Delete all meals for a date
./scripts/delete-meal.sh --date 2026-04-06

# Delete today's preset meals
./scripts/delete-meal.sh --preset 平日昼間

# Delete preset meals for a specific date
./scripts/delete-meal.sh --preset 平日昼間 --date 2026-04-05
```

### Output

- **stdout**: JSON array of deleted meal timestamps (for HealthKit cleanup)
  ```json
  ["2026-04-06T07:30:00+09:00", "2026-04-06T07:30:01+09:00"]
  ```
- **stderr**: `Deleted N meals`

### iOS Shortcut integration

The Shortcut uses the returned timestamps to find and delete corresponding HealthKit samples:

1. SSH: `delete-meal.sh --preset 平日昼間 --date <date>`
2. Parse JSON array of timestamps
3. For each timestamp: Find Health Samples → Delete Health Samples

---

## reset-reminders.sh

FoodLog リマインダーリスト内の未完了リマインダーをすべて完了済みにする。launchd で毎朝5:00に自動実行されるが、手動実行も可能。

### 使い方

```bash
# 手動実行
./scripts/reset-reminders.sh
```

### 自動実行

`~/Library/LaunchAgents/com.tkura.foodlog.reset-reminders.plist` により毎日5:00に自動実行。

```bash
# 登録確認
launchctl list | grep foodlog

# 手動で無効化
launchctl unload ~/Library/LaunchAgents/com.tkura.foodlog.reset-reminders.plist

# 再有効化
launchctl load ~/Library/LaunchAgents/com.tkura.foodlog.reset-reminders.plist
```

### ログ

実行ログは `data/reset-reminders.log` に出力される。

---

## test-analyze.sh

Claude CLIが現在の環境で正しく動作するか確認するデバッグスクリプト。

### 使い方

```bash
./scripts/test-analyze.sh
```

### 動作内容

1. 環境情報（PATH、HOME、SHELL、TERM）をデバッグログに記録
2. `echo "hello" | claude -p "Say hi"` を実行し、stdout/stderrをキャプチャ
3. 結合したデバッグログを出力

`analyze.sh` が非対話SSHセッションで失敗する場合の原因調査に使用する。

---

## test-ssh.sh

iOS ShortcutからSSH接続した際の環境を確認するデバッグスクリプト。

### 使い方

```bash
./scripts/test-ssh.sh [引数...]
```

### 動作内容

1. 環境情報（PATH、PWD、引数、`claude` のパス）をデバッグログに追記
2. テスト用JSONを出力：`{"test": "hello from Mac", "status": "ok"}`

iOS ShortcutからMacにSSH接続してスクリプトを実行できるか検証する際に使用する。
