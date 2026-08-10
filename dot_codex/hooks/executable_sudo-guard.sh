#!/usr/bin/env bash
# Codex PreToolUse hook (matcher: Bash).
# Deny commands that invoke sudo unless a valid global sudo timestamp exists.
set -euo pipefail

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

# Match sudo only in command position, not as plain text or an argument.
if ! printf '%s' "$command" |
  grep -Eq '(^|[;&|({`]|\$\()[[:space:]]*sudo([[:space:]]|$)'; then
  exit 0
fi

# A cached sudo timestamp makes `sudo -n true` succeed without prompting.
if sudo -n true 2>/dev/null; then
  exit 0
fi

cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: this command needs sudo, but no valid sudo timestamp is cached. STOP — do not retry or work around it. Tell the user verbatim: run `sudo -v` in any terminal (type your password once; valid about 15 minutes via the global timestamp), then say 'done' and I'll continue. When the task is finished they can revoke it early with `sudo -K`."
  }
}
EOF
