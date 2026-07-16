# migrate_zsh_config

One-time, per-machine migration of the oh-my-zsh setup from the old chezmoi
`archive` externals to the new `git-repo` externals + `ZSH_CUSTOM` layout.
After it runs, oh-my-zsh no longer shows up in `chezmoi diff`.

`migrate_zsh_config.sh` is safe to re-run: it no-ops when the machine is already
migrated, backs up `~/.oh-my-zsh` and `~/.zshrc` before touching them, and rolls
back on failure.

## Prerequisite (once)

The migration must already be **committed and pushed from the primary machine**
— the script refuses to run against a source repo that doesn't yet define the
new externals.

## Run it on a machine

Recommended — run straight from the chezmoi source, no full apply:

```sh
chezmoi git pull
bash "$(chezmoi source-path ~/.config/agent_context/migrate_zsh_config/migrate_zsh_config.sh)" --no-pull
```

Why this is safe: `chezmoi git pull` only updates the source repo — it never
writes to `$HOME`, so it can't trigger the oh-my-zsh clone. **Do not** run a
full `chezmoi apply` / `chezmoi update` on an un-migrated machine first: it would
try to clone `~/.oh-my-zsh` while the old dir is still populated and either
prompt or fail. Let this script handle `~/.oh-my-zsh` (it uses `--force`).

Alternative — materialize the file with a *scoped* apply, then run it:

```sh
chezmoi git pull
chezmoi apply ~/.config/agent_context/migrate_zsh_config   # scoped: touches only this dir
bash ~/.config/agent_context/migrate_zsh_config/migrate_zsh_config.sh --no-pull
```

## After it succeeds

```sh
exec zsh                        # reload the shell
# then delete the backups it printed, e.g.:
rm -rf ~/.oh-my-zsh.bak-*       # and ~/.zshrc.bak-* once you're happy
```

## Many machines

```sh
for h in host1 host2 host3; do
  echo "=== $h ==="
  ssh "$h" 'chezmoi git pull && bash "$(chezmoi source-path ~/.config/agent_context/migrate_zsh_config/migrate_zsh_config.sh)" --no-pull'
done
```

From the next update onward, migrated machines run a plain `chezmoi update` with
no oh-my-zsh diff noise.
