#!/usr/bin/env bash
#
# migrate_zsh_config.sh
#
# Migrate this machine from the OLD oh-my-zsh chezmoi layout (everything under
# ~/.oh-my-zsh delivered as `archive` externals, which show up as drift in
# `chezmoi diff`) to the NEW layout:
#
#   ~/.oh-my-zsh            -> git-repo external (its contents are never diffed)
#   ~/.oh-my-zsh-custom/... -> plugins & themes as git-repo externals, plus the
#                              hand-authored theme as a chezmoi source file
#   ZSH_CUSTOM              -> set in ~/.zshrc to point at ~/.oh-my-zsh-custom
#
# A git-repo external cannot clone into a non-empty directory, so the existing
# ~/.oh-my-zsh is moved aside first. The script then applies the new config with
# --force (so it never blocks on a TTY "overwrite?" prompt), verifies the result,
# and restores the backup if anything fails.
#
# Safe to re-run: it no-ops on an already-migrated machine.
#
# This script lives outside $PATH; invoke it explicitly, e.g.:
#   bash ~/.config/agent_context/migrate_zsh_config/migrate_zsh_config.sh
# See README.md in the same directory for the full per-machine procedure.
#
# Flags:
#   --no-pull   migrate using the local chezmoi source as-is (skip `git pull`)
#   -h|--help   show this header

set -euo pipefail

usage() { sed -n '2,/^set -/{/^set -/d;s/^# \{0,1\}//;p;}' "$0"; }

NO_PULL=0
for arg in "$@"; do
  case "$arg" in
    --no-pull) NO_PULL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

OMZ="$HOME/.oh-my-zsh"
CUSTOM="$HOME/.oh-my-zsh-custom"
ZSHRC="$HOME/.zshrc"
STAMP="$(date +%Y%m%d-%H%M%S)"
OMZ_BAK="$OMZ.bak-$STAMP"
ZSHRC_BAK="$ZSHRC.bak-$STAMP"

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

command -v chezmoi >/dev/null 2>&1 || die "chezmoi is not installed / not on PATH."
command -v git     >/dev/null 2>&1 || die "git is required by the new git-repo externals but was not found on PATH."

is_migrated() {
  grep -qs 'ZSH_CUSTOM=.*oh-my-zsh-custom' "$ZSHRC" \
    && [ -d "$CUSTOM/plugins" ] \
    && [ -n "$(ls -A "$CUSTOM/plugins" 2>/dev/null || true)" ] \
    && git -C "$OMZ" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

if is_migrated; then
  log "Already on the new git-repo / ZSH_CUSTOM layout — nothing to do."
  exit 0
fi

if [ "$NO_PULL" -eq 0 ]; then
  log "Pulling latest chezmoi source..."
  chezmoi git pull \
    || die "could not pull the chezmoi source; resolve it manually and re-run, or pass --no-pull."
fi

# The pulled source must actually contain the new externals, otherwise this
# machine would be migrated against stale config. This guards against running
# before the migration commit has been pushed from the primary machine.
SRCDIR="$(chezmoi source-path)"
grep -qs 'oh-my-zsh-custom' "$SRCDIR/.chezmoiexternal.toml" \
  || die "the chezmoi source does not define the new oh-my-zsh-custom externals yet.
       Commit & push the migration from your primary machine first, then re-run."

# --- move the old framework dir aside so the git-repo external can clone -------
if [ -e "$OMZ" ]; then
  log "Backing up existing $OMZ -> $OMZ_BAK"
  mv "$OMZ" "$OMZ_BAK"
else
  OMZ_BAK=""
fi

# --force will overwrite ~/.zshrc with the managed version; keep a copy in case
# this machine had local, unmanaged edits to it.
if [ -f "$ZSHRC" ]; then
  cp -p "$ZSHRC" "$ZSHRC_BAK"
else
  ZSHRC_BAK=""
fi

restore() {
  warn "apply failed — rolling back."
  if [ -n "$OMZ_BAK" ] && [ -d "$OMZ_BAK" ]; then
    rm -rf "$OMZ" 2>/dev/null || true
    mv "$OMZ_BAK" "$OMZ"
    warn "restored $OMZ from backup."
  fi
}
trap restore ERR

# --- apply the new config (scoped, so unrelated drift never prompts) -----------
log "Applying new config: git-repo externals + ZSH_CUSTOM (this clones a few repos)..."
chezmoi apply --force --refresh-externals "$OMZ" "$CUSTOM" "$ZSHRC"
trap - ERR

# --- verify --------------------------------------------------------------------
log "Verifying..."
fail=0
git -C "$OMZ" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { warn "$OMZ is not a git checkout"; fail=1; }
[ -n "$(ls -A "$CUSTOM/plugins" 2>/dev/null || true)" ] \
  || { warn "$CUSTOM/plugins is empty"; fail=1; }
grep -qs 'ZSH_CUSTOM=.*oh-my-zsh-custom' "$ZSHRC" \
  || { warn "ZSH_CUSTOM is not set in $ZSHRC"; fail=1; }
drift="$(chezmoi status "$OMZ" "$CUSTOM" 2>/dev/null | wc -l | tr -d ' ')"
[ "$drift" = "0" ] \
  || warn "chezmoi still reports $drift changed path(s) here (inspect: chezmoi diff $OMZ $CUSTOM)"

[ "$fail" -eq 0 ] || die "verification failed (see warnings). Backup kept at ${OMZ_BAK:-<none>}."

# --- done ----------------------------------------------------------------------
log "Migration complete."
echo
echo "  Next steps:"
echo "    reload your shell:        exec zsh"
echo "    when it looks right, rm:  ${OMZ_BAK:-'(no oh-my-zsh backup was needed)'}"
[ -n "$ZSHRC_BAK" ] && echo "                              $ZSHRC_BAK"
echo
echo "  From now on this machine updates with a plain 'chezmoi update' —"
echo "  oh-my-zsh will no longer appear in 'chezmoi diff'."
