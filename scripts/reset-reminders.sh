#!/bin/bash
# Mark all incomplete reminders in the "Foodlog" list as completed.
# Uses reminders-cli (EventKit) instead of osascript (AppleEvents)
# so it works even when the Mac is asleep or screen is locked.
# Designed to run daily at 5:00 AM via launchd, but can also be run manually.
#
# Usage:
#   ./scripts/reset-reminders.sh

set -euo pipefail

if [ -x /usr/local/bin/reminders ]; then
    REMINDERS=/usr/local/bin/reminders        # Intel macOS / Homebrew on /usr/local
elif [ -x /opt/homebrew/bin/reminders ]; then
    REMINDERS=/opt/homebrew/bin/reminders     # Apple Silicon / Homebrew on /opt/homebrew
else
    REMINDERS=$(command -v reminders 2>/dev/null || echo "")
fi

if [ -z "$REMINDERS" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: reminders CLI not found" >&2
    exit 1
fi

LIST="Foodlog"
LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')]"

# Get the count of incomplete reminders
COUNT=$("$REMINDERS" show "$LIST" 2>/dev/null | grep -c '^[0-9]' || true)

if [[ "$COUNT" -eq 0 ]]; then
    echo "$LOG_PREFIX No incomplete reminders in $LIST."
    exit 0
fi

# Complete reminders from highest index to lowest to avoid index shifting
for (( i = COUNT - 1; i >= 0; i-- )); do
    "$REMINDERS" complete "$LIST" "$i" >/dev/null 2>&1 || {
        echo "$LOG_PREFIX ERROR: Failed to complete reminder at index $i" >&2
    }
done

echo "$LOG_PREFIX Marked $COUNT reminder(s) as completed in $LIST."
