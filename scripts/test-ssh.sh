#!/bin/bash
# Debug script to test what SSH from iOS Shortcut actually does
LOG="$HOME/GIT/food_log/data/ssh-debug.log"

echo "=== $(date) ===" >> "$LOG"

# Output base64-encoded JSON (same method as analyze.sh)
echo '{"meal_id":"test","totals":{"calories":123,"protein_g":10},"meal_description":"テスト食事"}' | base64
