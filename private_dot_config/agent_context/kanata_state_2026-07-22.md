# kanata setup — state snapshot as of 2026-07-22 (SIMPLIFIED)

Authoritative description of how kanata runs on this machine after the **2026-07-22
simplification**. This supersedes `kanata_state_2026-06-22.md`, `kanata_main_build_setup.md`,
`kanata_move_to_prerelease.md`, and `kanata_post_sleep_recovery.md` — all of which describe the
older custom-source-build + multi-watchdog design that was torn down. `kanata_setup_doc.md`
(in `~/.local/bin`) still describes this two-job design and is broadly accurate.

## Why we simplified

The previous setup ran a self-built `main` binary (`/usr/local/bin/kanata-main-40a8b17`) plus
three recovery layers (sleepwatcher wake hook, pmset wake-watchdog, vk-agent log trigger). It was
fragile and *still* crashed after sleep. Stable **kanata 1.12.0** shipped to Homebrew (Jul 2026)
carrying the same macOS wake fixes the custom build had (#2041 crash-safe restart, #2013 sink
auto-recovery), so the custom build no longer bought anything. We reverted to a single, minimal
setup and accept an occasional manual `launch_kanata.sh restart` over the watchdog complexity.

## What runs now — two launchd jobs, no watchdogs

| Job | Runs as | Where | What |
|-----|---------|-------|------|
| `dev.kanata.kanata` | root | `/Library/LaunchDaemons/dev.kanata.kanata.plist` | `/opt/homebrew/bin/kanata -c ~/.config/kanata/my_config.kbd -p 5829`, `KeepAlive{SuccessfulExit:false}`, `RunAtLoad`. The keyboard remapper. |
| `dev.kanata.vk-agent` | your user | `~/Library/LaunchAgents/dev.kanata.vk-agent.plist` | `/opt/homebrew/bin/kanata-vk-agent -p 5829 -b net.kovidgoyal.kitty`. App-aware layer switching; connects to kanata's TCP server. |

Recovery is now just: kanata 1.12.0's own post-wake sink/grab recovery + launchd `KeepAlive`
(restarts on a hard crash). The sleepwatcher/`dev.kanata.wake`, `dev.kanata.wake-watchdog`, and
`dev.kanata.vkagent-trigger` daemons and their scripts were all removed, and `sleepwatcher` was
`brew uninstall`ed.

## Binary & config

- **Binary:** `/opt/homebrew/bin/kanata` — Homebrew stable, updated by `brew upgrade`. No more
  pinned custom-path binary. (`kanata` is tracked in the chezmoi Brewfile.)
- **Why NOT `brew services`:** Homebrew's service block runs `kanata --no-wait --cfg
  ~/.config/kanata/kanata.kbd` with **no `-p`**, and kanata's TCP port is a CLI-only flag. The
  vk-agent needs the port, so we keep the tiny LaunchDaemon (with explicit `-p 5829`) instead.
- **Config:** `~/.config/kanata/my_config.kbd` (chezmoi-managed, stable path).
- **TCP port:** `5829` — must match in the daemon (`-p`) and the vk-agent (`-p`).

## macOS permissions (the #1 gotcha — unchanged)

`/opt/homebrew/bin/kanata` needs **BOTH** in System Settings → Privacy & Security:
**Input Monitoring** AND **Accessibility**. The vk-agent needs **Accessibility** too (to read the
frontmost app). TCC is keyed to the resolved binary path.

> **Upgrade caveat:** `/opt/homebrew/bin/kanata` resolves to the versioned Cellar path
> (`/opt/homebrew/Cellar/kanata/<ver>/bin/kanata`). A `brew upgrade kanata` that bumps the version
> changes that path, so you must **re-grant both permissions** to the new binary afterward.
> Symptom of a missing grant: log says `keyboard grabbed` but keys aren't remapped, or
> `IOHIDDeviceOpen ... not permitted`.

## Karabiner

Karabiner-Elements is installed **only** for its DriverKit Virtual HID device; its own **grabber**
is disabled (it would fight kanata). `karabiner-elements` is `brew pin`ned on purpose — it keeps the
DriverKit version compatible with kanata's bundled `karabiner-driverkit`. Leave that pin in place.

## Logs & operation

- Daemon: `/var/log/kanata.log` (has ANSI colour → `grep -a`, strip with `sed -E
  's/\x1b\[[0-9;]*m//g'`).
- vk-agent: `~/.local/log/kanata-vk-agent.log`.
- Manual control: `~/.local/bin/launch_kanata.sh {start|stop|restart|status|logs}`.

## If it crashes after sleep again

1. `~/.local/bin/launch_kanata.sh restart` — fastest fix.
2. If that doesn't re-grab, check `/var/log/kanata.log` for `not permitted` (→ re-grant TCC) or
   `driver version matched: false` (→ Karabiner DriverKit / kanata version mismatch).
3. Only if post-sleep crashes become frequent again should you consider re-adding a *single*
   wake hook — but try living with the occasional manual restart first; that was the whole point of
   this simplification.
