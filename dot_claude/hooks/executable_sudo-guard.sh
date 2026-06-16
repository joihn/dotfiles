#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash)
# If a Bash command invokes `sudo` but no valid sudo timestamp exists, deny the
# tool call and tell Claude to stop and ask the user to run `sudo -v`.
#
# Relies on the global sudo timestamp (Defaults timestamp_type=global) so that a
# `sudo -v` run in *any* terminal is visible to this hook process.
set -euo pipefail

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

# Does `sudo` appear in *command position* (not as an argument or inside a
# quoted string)? grep tests each physical line, so `^` covers line starts and
# command continuations; the class covers pipes, &&, ||, ;, subshells, $( ), etc.
if ! printf '%s' "$command" | grep -Eq '(^|[;&|({`]|\$\()[[:space:]]*sudo([[:space:]]|$)'; then
  exit 0
fi

# Valid (cached) sudo timestamp already? Allow.
if sudo -n true 2>/dev/null; then
  exit 0
fi

# No valid timestamp — block and instruct Claude to ask the user.
cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: this command needs sudo, but no valid sudo timestamp is cached. STOP — do not retry, do not work around it. Tell the user verbatim: run `sudo -v` in any terminal (type your password once; valid ~15 min via the global timestamp), then say 'done' and I'll continue. When the task is finished they can revoke early with `sudo -K`."
  }
}
EOF
exit 0
