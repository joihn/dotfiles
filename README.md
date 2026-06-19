# Dotfiles (chezmoi)

Cross-platform dotfiles managed with [chezmoi](https://www.chezmoi.io/), shared
between **macOS** and **Debian/Ubuntu Linux** machines. The same source tree
renders per-machine via Go templates, and a layered set of scripts bootstraps a
fresh machine end-to-end: package manager → prerequisites → packages → dotfiles.

> Source directory: `~/.local/share/chezmoi`. The "target" is `$HOME`.

---

## Quick start

### Fresh machine

```sh
sh ~/.local/share/chezmoi/private_dot_config/executable_auto_deploy.sh
# or, before the repo exists, the equivalent one-liner it runs:
sh -c "$(curl -fsLS https://chezmoi.io/get)" -- init --apply joihn
```

`auto_deploy.sh` is the Tier-0 bootstrap (see [Bootstrap order](#bootstrap-order)):
it seeds `git`/`curl`, drops in a usable zsh, then `chezmoi init --apply` clones
this repo and runs everything below.

### Day-to-day

```sh
chezmoi apply              # render + apply changes to $HOME
chezmoi diff               # preview what would change
chezmoi edit ~/.zshrc      # edit a managed file in the source tree
chezmoi cd                 # jump into the source directory
chezmoi managed            # list everything chezmoi controls
```

`git.autoCommit` / `autoPush` are **on** (see `.chezmoi.yaml.tmpl`), so changes
made via `chezmoi` are committed and pushed automatically. Direct edits in the
source tree are not — commit those yourself.

---

## How it works

### Naming conventions

chezmoi derives the target file from attribute prefixes in the source filename:

| Source name                         | Becomes / means                                    |
| ----------------------------------- | -------------------------------------------------- |
| `dot_zshrc`                         | `~/.zshrc`                                          |
| `private_dot_config/`               | `~/.config/` with `0600`/`0700` perms              |
| `executable_brewdiff`               | `~/.local/bin/brewdiff`, `+x`                       |
| `*.tmpl`                            | rendered as a Go template before being written     |
| `run_once_before_*`                 | script: runs once per machine, **before** updates  |
| `run_onchange_*`                    | script: re-runs whenever its rendered content changes |

### Application order

Every `chezmoi apply` follows chezmoi's fixed
[application order](https://www.chezmoi.io/reference/application-order/):

1. `run_before_` scripts (alphabetical)
2. **update phase** — files, dirs, **externals**, plain `run_` scripts, symlinks
3. `run_after_` scripts (alphabetical)

We exploit phase 1 to install the package manager and OS prerequisites before
anything in phase 2 needs them.

### Bootstrap order

A fresh machine is set up in two tiers:

**Tier 0 — `private_dot_config/executable_auto_deploy.sh`** (run by hand, once,
*before* chezmoi exists). Seeds `git`/`curl` on Linux so the repo can be cloned,
installs a static zsh to land in, then `chezmoi init --apply`.

**Tier 1 — `.chezmoiscripts/`** (run automatically inside every apply, in the
`run_before_` phase; ASCII-ordered by the numeric prefix):

| Script                                          | OS    | Does                                                                 |
| ----------------------------------------------- | ----- | -------------------------------------------------------------------- |
| `run_once_before_00-install-package-manager.sh` | both  | Installs **Homebrew** unattended (`NONINTERACTIVE=1`). On Linux, apt-installs linuxbrew prereqs (`build-essential procps curl file git`) first. |
| `run_once_before_10-install-system-prereqs.sh`  | linux | apt-installs GUI/system pkgs brew shouldn't own: `vim-gtk3 xclip sshfs` (+ `mpv` on x86_64 GNOME). |

These are `run_once_` (one-time machine setup), idempotent, and **never `set -e`**
so a recoverable failure (no network, no sudo, in Docker) doesn't abort the apply.
They are in `.chezmoiscripts/` so they're treated as scripts only and don't create
any file in `$HOME`.

> **Scripts don't share env.** Each runs in its own shell, so `PATH` set in `00`
> does not reach `10` or the brew-bundle script — every brew-dependent script
> locates `brew` by absolute path.

### Package management

The split is deliberate: **Homebrew is the unified CLI package manager on both
OSes**; apt only covers what brew can't (GUI/X11/FUSE builds) and the linuxbrew
bootstrap prereqs.

- `.chezmoitemplates/Brewfile` — single source of truth for brew packages.
  Lives in `.chezmoitemplates/` so it is **not** copied into `$HOME`; it's only
  inlined by reference. Cross-platform CLI formulae sit in the top (unguarded)
  section; a `{{ if eq .chezmoi.os "linux" }}` block holds tools that ship with
  the system on macOS (`git`, `zsh`); a `{{ if eq .chezmoi.os "darwin" }}` block
  holds all casks / `mas` / `tap` lines.
- `run_onchange_install-brew-packages.sh.tmpl` — runs `brew bundle` with the
  rendered Brewfile inlined. Re-runs only when that rendered content changes.
- `.chezmoitemplates/cursor-extensions` — one Cursor extension id per line.
- `run_onchange_install-cursor-extensions.sh.tmpl` — `cursor --install-extension`
  for each id; skips cleanly if there's no `cursor` CLI.
- `~/.local/bin/brewdiff` — shows drift between the tracked Brewfile and what's
  actually installed.

**Rules**

- **Only high-level packages** are tracked (what `brew bundle dump` emits =
  `brew leaves` + casks), never transitive deps — brew reinstalls those itself.
- **Casks are macOS-only** (Homebrew Cask doesn't exist on linuxbrew), so every
  `cask`/`mas`/`tap` line goes in the darwin block. Cross-platform CLI formulae
  go in the top (unguarded) section — verify each has a Linux bottle first.
- `git` / `zsh` are in the **linux-only** block: macOS uses its built-in
  `/bin/zsh` and Xcode CLT `git`; brew supplies them only where the system
  doesn't. (For any tool present in both, PATH order decides — `eval
  "$(brew shellenv)"` in `.zshrc` prepends brew's bin dir, so brew's wins.)
- `kanata-vk-agent` is pinned manually (brew marks it not-on-request, so
  `brew bundle dump` won't list it); it shows as expected drift in `brewdiff`.

**Common tasks**

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

**Adding a brew package**

1. Install it normally (`brew install foo` / `cursor --install-extension bar`).
2. Run `brewdiff` (brew) or re-dump the cursor list (above).
3. Add the line to the right block in the source file — for a brew formula,
   confirm it has a Linux bottle before putting it in the cross-platform section:
   `curl -fsSL https://formulae.brew.sh/api/formula/<name>.json | jq '.bottle.stable.files|keys'`
4. `chezmoi apply` (or just commit — it'll install on the next machine).

**App Store (mas)**

`brew "mas"` is tracked. To add apps: `mas list`, then add `mas "Name", id: 123`
lines to the darwin block. Caveat: `mas` only reinstalls apps tied to your Apple
ID and is flaky on recent macOS.

### macOS defaults (`defaults write`)

macOS preferences live in plists. We track them the portable, diffable way — an
explicit list of `defaults write` commands, **not** copied binary plists.

- `run_onchange_after_apply-macos-defaults.sh.tmpl` — the single source of truth.
  An OS-guarded (`{{ if eq .chezmoi.os "darwin" }}`) list of `defaults write`
  lines (real values captured from a live machine), grouped by area (Keyboard,
  Dock, Finder, Screenshots, Spotlight) plus per-app prefs: Shottr
  (`cc.ffitch.shottr`), Contexts (`com.contextsformac.Contexts`), Maccy
  (`org.p0deje.Maccy`). It ends by `killall`-ing Dock / Finder / SystemUIServer /
  Spotlight so changes apply without a logout.
- **App pref capture rule**: cherry-pick the user-facing keys; exclude volatile /
  machine-specific keys (install ids, usage counters, telemetry/AppCenter,
  Sparkle `SU*` update state, window position/size). That exclusion — not the
  value itself — is what prevents cross-machine conflicts.
- **Not tracked here**: LinearMouse uses its own JSON
  (`private_dot_config/linearmouse/linearmouse.json`), not `defaults`.
  BetterDisplay is deliberately skipped — its real config is keyed per-monitor by
  hardware tag-id/EDID and isn't portable between machines.
- **Spotlight categories gotcha**: the disabled categories are stored in
  `com.apple.Spotlight` → `EnabledPreferenceRules`, which (despite the name) is
  the list of categories turned **OFF** — verified empirically: enabling a
  category *removes* its id, disabling *adds* it. We capture that array verbatim.
  To change it, toggle in System Settings > Spotlight, then re-capture with
  `defaults read com.apple.Spotlight EnabledPreferenceRules | grep -oE '"[^"]+"'`.
- `run_onchange_` + idempotent `defaults write` ⇒ it re-applies automatically
  whenever you edit the list, and is a cheap no-op otherwise. Renders to nothing
  (never runs) on Linux.
- Only **portable** prefs belong here. ByHost/UUID prefs (e.g. menu-bar icon
  order, under `~/Library/Preferences/ByHost/`) are machine-specific — skip them.
- App prefs are **cherry-picked** (only the keys that matter), never whole-plist
  dumps — many apps pollute their domain with telemetry / device IDs.

**Adding a setting** — let the helper find the exact line for you:

```sh
macos-pref-diff                 # snapshot → toggle ONE setting in System Settings → diff
macos-pref-diff cc.ffitch.shottr  # scope to one app's domain (less noise)
# paste the printed `defaults write ...` line into the right section, then:
chezmoi edit --apply ~/.local/share/chezmoi  # or just: chezmoi apply
```

This script is at the repo root (not a partial), so plain `chezmoi edit` reaches
it; or open `$(chezmoi source-path)/run_onchange_after_apply-macos-defaults.sh.tmpl`.

### Default apps — "Open with" (`duti`)

File-type and URL-scheme handlers are **not** `defaults` keys — they live in the
LaunchServices database (`com.apple.launchservices.secure.plist`), a
machine-specific binary plist you must not copy. We set them declaratively with
[`duti`](https://github.com/moretension/duti) (tracked in the Brewfile).

- `.chezmoitemplates/duti-settings` — single source of truth, one
  `app-bundle-id  .ext  role` line per association (same partial pattern as the
  Brewfile). Only **non-Apple** handlers are tracked (Sublime, Cursor, Chrome,
  Acrobat, Warp…); stock Apple defaults are left alone to minimise conflicts.
- `run_onchange_after_apply-duti-defaults.sh.tmpl` — strips `#` comments/blanks
  (duti has no comment syntax) and pipes the list to `duti`. Idempotent; skips
  cleanly if `duti` isn't installed.
- `~/.local/bin/duti-dump` — prints your current custom handlers as ready-to-paste
  `duti-settings` lines (`duti-dump` for a common list, or `duti-dump md py …`).
  It comments out extensions with no stable UTI (see below) so they never break
  the applier.
- **UTI limitation**: duti can only bind an extension that has a *stable* UTI.
  Extensions with none (e.g. `.go .vue .dockerfile .rs .conf` — anything no
  installed app declares) resolve to a per-machine dynamic `dyn.*` UTI that
  LaunchServices refuses to set (`error -50`). Those are kept commented at the
  bottom of `duti-settings` to record intent; set them per machine via Finder's
  "Open With → Always Open With". `duti-dump` flags them automatically.

### Externals (`.chezmoiexternal.toml`)

Third-party content pulled in at apply time (refreshed on a `refreshPeriod`):

- **oh-my-zsh** → `~/.oh-my-zsh` (`type = "archive"`).
- **zsh plugins** (`fast-syntax-highlighting`, `zsh-vi-mode`, `conda-zsh-completion`,
  `zsh-autosuggestions`) → `~/.oh-my-zsh/custom/plugins/*`. These are
  `type = "archive"` (GitHub tarballs over HTTPS) **on purpose**: archives need
  no `git` binary, so a fresh machine can fetch them before git is even installed.
- **kitten** (Linux only) → `~/.local/bin/kitten`, an arch-aware static binary for
  clipboard passthrough over SSH. On macOS it comes from `cask "kitty"`.

### Templates & machine differences

`*.tmpl` files render with Go templates. OS branching uses `.chezmoi.os`:

```
{{ if eq .chezmoi.os "darwin" }} ... {{ else if eq .chezmoi.os "linux" }} ... {{ end }}
```

A `.tmpl` script that renders to empty (e.g. the Linux-only `10-` script on macOS)
is simply **not executed**. `dot_zshrc` additionally branches at runtime on
`$OSTYPE` / `$HOST` to set `$OS`/`$MACHINE` and to `eval` the right `brew shellenv`
(linuxbrew vs `/opt/homebrew`).

### Config (`.chezmoi.yaml.tmpl`)

```yaml
diff:  { pager: delta }           # use git-delta for `chezmoi diff`
git:   { autoCommit: true, autoPush: true }
data:  { DISPLAY_VAR: <$DISPLAY or :1> }   # consumed by templates
```

---

## Repository map

```
.chezmoi.yaml.tmpl        chezmoi config (pager, autoCommit/Push, data vars)
.chezmoiexternal.toml     oh-my-zsh + plugins + kitten (external downloads)
.chezmoiignore            files never applied (config_terminator, copyq.conf, warp_config.json)
.chezmoiscripts/          Tier-1 bootstrap (run_once_before_ package-manager + prereqs)
.chezmoitemplates/        Brewfile, cursor-extensions (partials, NOT written to $HOME)
run_onchange_install-brew-packages.sh.tmpl      brew bundle the Brewfile
run_onchange_install-cursor-extensions.sh.tmpl  install tracked Cursor extensions
run_onchange_after_apply-macos-defaults.sh.tmpl macOS `defaults write` settings (darwin only)
run_onchange_after_apply-duti-defaults.sh.tmpl  default "Open with" handlers via duti (darwin only)
dot_*                     ~/.* dotfiles (zshrc, bashrc, p10k.zsh, tmux.conf, vimrc, ...)
dot_local/bin/            helper scripts (see below) → ~/.local/bin
private_dot_config/       ~/.config/* (nvim, kitty, btop, kanata, ...)
private_dot_config/executable_auto_deploy.sh    Tier-0 fresh-machine bootstrap
private_Library/          macOS ~/Library bits
```

### Helper scripts (`~/.local/bin`)

A few worth knowing (full list in `dot_local/bin/`):

- `brewdiff` — Brewfile vs installed drift (see above).
- `chezlg` — git config swap helper around lazygit.
- `gdf` — browse/preview git diffs through fzf + delta.
- `launch_kanata.sh` — start the kanata keyboard remapper.
- `macos-pref-diff` — snapshot/diff `defaults` to find the key a setting changes.
- `macos-defaults-check` — dry-run: which tracked `defaults` differ from this
  machine (what `chezmoi apply` would actually change; `chezmoi diff` can't show it).
- `duti-dump` — print current custom "Open with" handlers as duti settings lines.
- `plist_inspect` — fzf-browse macOS `defaults` domains with previews.

---

## Conventions for editing this repo

- **Template partials** (`Brewfile`, `cursor-extensions`) can't be reached by
  `chezmoi edit` — open them directly under `$(chezmoi source-path)/.chezmoitemplates/`.
- Keep bootstrap scripts **idempotent** and tolerant of Docker / no-sudo / root.
- Put a brew formula in the cross-platform block only if it has a Linux bottle;
  casks/mas/taps are macOS-only.
- After changing a `run_onchange_` script's *rendered* output, the next `apply`
  re-runs it; that's by design.

## Verifying changes

```sh
chezmoi execute-template < .chezmoiexternal.toml      # check a template renders
chezmoi execute-template < run_onchange_install-brew-packages.sh.tmpl  # see the brew list for THIS os
chezmoi apply --dry-run --verbose                     # full preview, no writes
chezmoi doctor                                        # environment health check
```

For a true fresh-machine test, run `auto_deploy.sh` inside a clean Debian
container and confirm: apt prereqs install, linuxbrew installs (as non-root),
plugin archives download without git, `brew bundle` runs, and a login zsh starts
with the plugins active.
