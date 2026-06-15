#!/usr/bin/env bash
# statusLine command. Renders the status line AND records the session's
# cumulative cost to a per-session file so the budget-guard PreToolUse hook
# can read it (hook stdin does not include cost; the statusline input does).

i=$(cat)

sid=$(printf '%s' "$i" | jq -r '.session_id // ""')
cost=$(printf '%s' "$i" | jq -r '.cost.total_cost_usd // 0')

# Record cost for the budget guard (best effort; never break the status line).
if [ -n "$sid" ]; then
  dir="$HOME/.claude/budget"
  mkdir -p "$dir" 2>/dev/null
  printf '%s' "$cost" > "$dir/$sid.cost" 2>/dev/null
fi

# Render the status line (same format as before).
model=$(printf '%s' "$i" | jq -r '.model.display_name // "?"')
ctx=$(printf '%s' "$i" | jq -r '.context_window.used_percentage // 0')
printf '%s · %s%% ctx · $%.2f' "$model" "$ctx" "$cost"
