# Package tracking workflow

How Homebrew packages and Cursor extensions are tracked in this chezmoi repo.

## Files

- `.chezmoitemplates/Brewfile` — single source of truth for brew packages.
  Lives in `.chezmoitemplates/` so it is **not** copied into `$HOME`; it's only
  inlined by reference. Has a `{{ if eq .chezmoi.os "darwin" }}` block for
  macOS-only entries.
- `.chezmoitemplates/cursor-extensions` — one Cursor extension id per line.
- `run_onchange_install-brew-packages.sh.tmpl` — runs `brew bundle` with the
  rendered Brewfile. Re-runs only when the rendered content changes.
- `run_onchange_install-cursor-extensions.sh.tmpl` — `cursor --install-extension`
  for each id; skips if no `cursor` CLI.
- `~/.local/bin/brewdiff` (`dot_local/bin/executable_brewdiff`) — shows drift
  between the tracked Brewfile and what's actually installed.

## Rules

- **Only high-level packages** are tracked (what `brew bundle dump` emits =
  `brew leaves` + casks), never transitive deps — brew reinstalls those itself.
- **Casks are macOS-only** (Homebrew Cask doesn't exist on linuxbrew), so every
  `cask`/`mas`/`tap` line goes in the darwin block. Cross-platform CLI formulae
  go in the top (unguarded) section — verified each has a Linux bottle.
- `goku` / `kanata-vk-agent` are pinned manually (brew marks them not-on-request,
  so `brew bundle dump` won't list them); they show as expected drift in brewdiff.

## Common tasks

```sh
# See what you've installed ad-hoc but haven't tracked yet:
brewdiff

# Edit the brew list (it's a template partial, so `chezmoi edit` won't reach it):
$EDITOR "$(chezmoi source-path)/.chezmoitemplates/Brewfile"

# Refresh the Cursor extension list from what's currently installed:
cursor --list-extensions > "$(chezmoi source-path)/.chezmoitemplates/cursor-extensions"

# Apply (installs anything new; both run_onchange scripts are idempotent):
chezmoi apply
```

## Adding a package

1. Install it normally (`brew install foo` / `cursor --install-extension bar`).
2. Run `brewdiff` (brew) or re-dump the cursor list (above).
3. Add the line to the right block in the source file — for a brew formula,
   confirm it has a Linux bottle before putting it in the cross-platform section:
   `curl -fsSL https://formulae.brew.sh/api/formula/<name>.json | jq '.bottle.stable.files|keys'`
4. `chezmoi apply` (or just commit — it'll install on the next machine).

## App Store (mas)

`brew "mas"` is tracked. To add apps: `mas list`, then add `mas "Name", id: 123`
lines to the darwin block. Caveat: `mas` only reinstalls apps tied to your Apple
ID and is flaky on recent macOS.
