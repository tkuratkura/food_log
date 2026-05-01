#!/bin/bash
# Debug: capture claude's error output
export PATH="$HOME/.local/bin:$PATH"
LOG="$HOME/GIT/food_log/data/meals/analyze-debug.log"
cd "$HOME/GIT/food_log"

echo "=== $(date) ===" > "$LOG"
echo "claude: $(which claude)" >> "$LOG"
echo "HOME: $HOME" >> "$LOG"
echo "SHELL: $SHELL" >> "$LOG"
echo "TERM: $TERM" >> "$LOG"

# Capture both stdout and stderr from claude
echo "hello" | claude -p "Say hi" > "$LOG.stdout" 2> "$LOG.stderr"
echo "exit: $?" >> "$LOG"
echo "--- stdout ---" >> "$LOG"
cat "$LOG.stdout" >> "$LOG"
echo "--- stderr ---" >> "$LOG"
cat "$LOG.stderr" >> "$LOG"

# Output for shortcut
cat "$LOG"
