# kanata setup — state snapshot as of 2026-06-22

A point-in-time description of how kanata is actually running on machine #1 right now. For the
*procedure* to reproduce it on another machine, see `kanata_main_build_setup.md` (the authoritative
build/runbook). For history of why we got here, see `kanata_post_sleep_recovery.md` (sleepwatcher +
Karabiner-grabber background) and `kanata_move_to_prerelease.md` (superseded prerelease attempt).

## What kanata is

kanata remaps the keyboard. On macOS it grabs the physical keyboard via IOKit and emits remapped
events through the **Karabiner-DriverKit-VirtualHIDDevice**. Karabiner-Elements is installed *only*
for that virtual device — its own **grabber** is disabled (it would fight kanata for the keyboard).

## Binary & config

- **Binary:** `/usr/local/bin/kanata-main-40a8b17` — a source build of `jtroo/kanata` `main`
  (commit `40a8b17`, 2026-06-16), reports `kanata 1.12.0-prerelease-2`. Pinned path so `brew upgrade`
  never touches it.
- **Why `main`, not stable:** stable 1.11.0 has no post-wake recovery; the 1.12.0 *prerelease* was a
  wake-crash regression (issue #2008). `main` carries the sink-disconnect fix (#2013) + crash-safe
  restart (#2041).
- **Config:** `/Users/maximegardoni/.config/kanata/my_config.kbd` (chezmoi-managed, stable path —
  deliberately NOT in the `~/code/kanata` git tree, so branch switches can't make the live config
  vanish). The config has `danger-enable-cmd yes` but no live `(cmd ...)` action, so the standard
  (non-`cmd_allowed`) binary is correct.
- **TCP port:** `5829` (the vk-agent connects here for app-aware layer switching).
- **Rollback to brew 1.11.0:** restore a `dev.kanata.kanata.plist.bak-*` and bootout/bootstrap; the
  brew binary at `/opt/homebrew/bin/kanata` is never modified.

## macOS permissions (the #1 gotcha)

The `main` build needs **BOTH** in System Settings → Privacy & Security:
- **Input Monitoring** AND **Accessibility**, granted to `/usr/local/bin/kanata-main-40a8b17`.

TCC is keyed to the exact binary path; because the daemon runs as **root** (UID 0) macOS can't show
the prompt, it silently denies. Symptom: log says `keyboard grabbed` but keys aren't remapped, with
`TCC deny IOHIDDeviceOpen` / `not permitted` in the unified log. A new binary path ⇒ re-grant both.

## launchd jobs (kanata + 3 recovery layers)

All are root LaunchDaemons. The kanata daemon plist lives at
`/Library/LaunchDaemons/dev.kanata.kanata.plist`; its source-of-truth template is
`~/.local/bin/dev.kanata.kanata.plist.new`. The recovery layers exist because kanata's keyboard grab
can die in several distinct ways, and each layer catches a class the others miss:

| Job | Mechanism | Failure class it catches |
|-----|-----------|--------------------------|
| `dev.kanata.kanata` | launchd `KeepAlive {SuccessfulExit:false}` | hard **crash** (process dies) |
| `dev.kanata.wake` | sleepwatcher `-w` → `kanata-wake-restart.sh` | **full** system wake |
| `dev.kanata.wake-watchdog` | `kanata-wake-watchdog.sh` on 15s `StartInterval`; re-grabs when `pmset`'s latest Wake/DarkWake is newer than kanata's process start | **DarkWake / scheduled-alarm** wake (sleepwatcher's `-w` misses these) |
| `dev.kanata.vkagent-trigger` | `kanata-vkagent-log-trigger.sh` tails the vk-agent log; fires on the `Broken pipe` line (45s process-age cooldown) | grab/socket death with **no system wake at all** (display-wake, power-adapter attach, virtual-HID churn) |

The wake-watchdog and vkagent-trigger both call `kanata-wake-restart.sh`, which carries a shared
self-expiring lock (`/tmp/kanata-wake.lock`, 45s stale) so the three layers never stomp each other.

### Why so many layers — the failures that drove each
- **2026-06-15:** keyboard dead after wake; brew 1.11.0 doesn't reconnect the DriverKit sink → moved
  off stable.
- **2026-06-19 10:00:** grab silently died on a `calaccessd` alarm wake; `-w` never fired → added the
  pmset **watchdog** (7b).
- **2026-06-22 10:23:** grab/socket died with **no system sleep** (display-wake + power-adapter attach
  + virtual-HID `IOHIDLibUserClient` open/close churn); both wake-based layers are blind to this → 
  added the symptom-based **vk-agent log trigger** (7c). The `Endel` app holds a permanent
  no-idle-sleep assertion, so what feels like "sleep" is usually just the display turning off.

## Logs & operation

- Daemon: `/var/log/kanata.log` (world-readable; has ANSI colour bytes → `grep -a`, strip with
  `sed -E 's/\x1b\[[0-9;]*m//g'`). The frequent `virtual_hid_keyboard_ready true` lines are a normal
  heartbeat, NOT a stuck loop.
- Wake/watchdog/trigger: `/var/log/kanata-wake.log` (prefixes: `wake:` vs `watchdog:` vs
  `vkagent-trigger:`).
- vk-agent: `~/.local/log/kanata-vk-agent.log`.
- Manual control: `~/.local/bin/launch_kanata.sh {start|stop|restart|status|logs}`.

## Files under chezmoi (this setup)

Scripts/plists in `~/.local/bin`: `launch_kanata.sh`, `kanata-wake-restart.sh`,
`kanata-wake-watchdog.sh`, `kanata-vkagent-log-trigger.sh`, and the plist templates
`dev.kanata.kanata.plist.new`, `dev.kanata.wake-watchdog.plist`, `dev.kanata.vkagent-trigger.plist`.
Config: `~/.config/kanata/my_config.kbd`. Docs: this dir (`~/.config/agent_context`).
The `/Library/LaunchDaemons/*.plist` live outside `$HOME`, so chezmoi tracks the `~/.local/bin`
templates and the install commands `sudo cp` them into place (see `kanata_main_build_setup.md`).

## Known open item

- **#2093 (deferred, not yet observed on this machine):** on `main`, a wake can rarely leave the
  DriverKit output sink unable to reconnect — log sticks on `Waiting for the output backend and
  console session to recover...` until `kickstart -k`. More likely with multiple kanata instances
  (we run one). Patch only if observed.
