#!/usr/bin/env bash
# PreToolUse hook. Hard-stops the session when cumulative cost reaches a budget.
#
# Cost comes from a per-session file written by the status line (record-cost.sh),
# because PreToolUse hook stdin does not include cost. Outputting
# {"continue": false, ...} is the only mechanism that stops the whole session;
# a PreToolUse "deny" would only block one tool and Claude would keep trying.
#
# Budget (USD) is read from CLAUDE_SESSION_BUDGET_USD, default 150.

input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // ""')

budget="${CLAUDE_SESSION_BUDGET_USD:-150}"
costfile="$HOME/.claude/budget/$sid.cost"

[ -n "$sid" ] || exit 0
[ -f "$costfile" ] || exit 0

cost=$(cat "$costfile" 2>/dev/null)
[ -n "$cost" ] || exit 0

over=$(awk -v c="$cost" -v b="$budget" 'BEGIN { print (c+0 >= b+0) ? 1 : 0 }')

if [ "$over" = "1" ]; then
  reason=$(printf 'Session budget reached: $%.2f spent >= $%.2f budget. Stopping the session. To continue, raise CLAUDE_SESSION_BUDGET_USD or delete %s' "$cost" "$budget" "$costfile")
  jq -nc --arg r "$reason" '{continue: false, stopReason: $r}'
fi

exit 0
