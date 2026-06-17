# Runbook: fix kanata "dead after sleep" on macOS (brew-stable + sleepwatcher wake daemon)

**Audience:** an AI agent (Claude Code) or human bringing a *second* macOS machine to the same
working state as machine #1, set up on **2026-06-17**.

> **This SUPERSEDES `kanata_move_to_prerelease.md`.** That older runbook told you to install
> kanata **1.12.0-prerelease-2**. Don't. In practice that prerelease is a *regression* on macOS:
> per upstream issue [#2008](https://github.com/jtroo/kanata/issues/2008) it crashes / wedges on
> wake (worst when you wake the laptop with a **keypress**), and **1.11.0 stable does not have that
> bug**. The maintainer states he has no macOS device and does not maintain macOS support
> ([#1357](https://github.com/jtroo/kanata/issues/1357)), so there is no upstream fix to wait for —
> the supported recovery is an external **restart-on-wake** wrapper, which is what this runbook sets up.

## The problem (symptom on the broken machine)

After the laptop wakes from sleep, kanata keeps running but the keyboard remaps silently stop
working. The daemon log (`/var/log/kanata.log`) is stuck endlessly printing:

```
virtual_hid_keyboard_ready true
virtual_hid_keyboard_ready true
...
```

with **no** fresh `entering the event loop` / `Starting kanata proper` after the wake. macOS tore
down kanata's IOHIDManager keyboard grab on sleep; kanata never re-grabs. The process is alive, so
`launchd` KeepAlive does **not** restart it (it only restarts on a *crash*).

## The fix (end state we want — same as machine #1)

1. kanata daemon runs the **Homebrew stable** binary (`/opt/homebrew/bin/kanata` on Apple Silicon),
   NOT the pinned `/usr/local/bin/kanata-1.12.0-pre2` prerelease.
2. **sleepwatcher** runs as a root LaunchDaemon (`dev.kanata.wake`) and, on every wake, runs
   `~/.local/bin/kanata-wake-restart.sh`, which hard-kickstarts the kanata daemon so it re-grabs
   the keyboard. The script waits for the HID driver to settle, debounces wake bursts with a
   self-expiring lock, and verifies+retries the restart.
3. The conflicting **Karabiner-Elements grabber** is disabled (it "hogs the virtual keyboard
   device" — confirmed in upstream discussion #1537). The Karabiner **VirtualHIDDevice** daemon,
   which kanata *requires*, stays running.

---

## Step 0 — discover THIS machine's specifics (do not copy machine #1's paths)

Usernames/arch differ between machines (machine #1 in the old doc was `maximegardoni`; this set of
machines uses `maxime`; yours may differ). Find the real values:

```bash
uname -m                                            # arm64 -> brew prefix /opt/homebrew ; x86_64 -> /usr/local
whoami; echo "$HOME"
which -a kanata; kanata --version                   # brew binary path + current version
ls -l /Library/LaunchDaemons/ | grep -i kanata      # daemon plist filename / label
cat /Library/LaunchDaemons/dev.kanata.kanata.plist  # note: Label, ProgramArguments (binary, -c config, -p port), log paths
pgrep -fl 'kanata|sleepwatcher|karabiner_grabber|VirtualHIDDevice-Daemon'
```

Set helpers for the rest of this doc:

```bash
BREW_PREFIX="$(brew --prefix)"                       # /opt/homebrew or /usr/local
KANATA_BIN="$BREW_PREFIX/bin/kanata"                 # the stable target binary
DAEMON_LABEL="dev.kanata.kanata"                     # adjust if your plist Label differs
```

> **sudo:** several steps need root. If you are an agent and hit a blocked-sudo message, ask the
> user to run `sudo -v` in a terminal and say "done" (see `temp_sudo_for_claude_code.md`).

## Step 1 — pull the synced dotfiles (gets the scripts)

chezmoi already carries the two helper scripts from machine #1:

- `~/.local/bin/launch_kanata.sh`        (updated: knows about the wake daemon)
- `~/.local/bin/kanata-wake-restart.sh`  (the wake hook — portable, no hardcoded user paths)

```bash
chezmoi update            # pull + apply latest dotfiles
ls -l ~/.local/bin/kanata-wake-restart.sh    # should exist and be +x
```

## Step 2 — point the kanata daemon back at the brew stable binary

First make sure brew's kanata is stable >= 1.11.0:

```bash
brew update && brew info kanata     # if not installed: brew install kanata
brew upgrade kanata 2>/dev/null || true
"$KANATA_BIN" --version             # expect 1.11.0 (or later STABLE; never a *-prerelease)
```

Edit `/Library/LaunchDaemons/dev.kanata.kanata.plist`: set the **first** `ProgramArguments` string
to `$KANATA_BIN` (e.g. `/opt/homebrew/bin/kanata`). Leave `-c <config>`, `-p <port>`, `UserName`
(root), KeepAlive and log paths unchanged. Then reload — because the plist *changed*, a plain
`kickstart` is not enough; you must bootout + bootstrap:

```bash
PLIST=/Library/LaunchDaemons/dev.kanata.kanata.plist
sudo cp "$PLIST" "${PLIST}.bak-$(date +%Y%m%d)"
# ...edit the binary path in $PLIST (Read/Edit, or sudoedit)...
sudo launchctl bootout system/$DAEMON_LABEL 2>/dev/null || true
sleep 1
sudo launchctl bootstrap system "$PLIST"
sleep 6
# stable 1.11.0's success markers (NOTE: it does NOT log "keyboard grabbed" like the prerelease did):
tail -n 200 /var/log/kanata.log | grep -avE 'virtual_hid_keyboard_ready' | tail -n 8
# want to see: "entering the processing loop" / "entering the event loop" / "Starting kanata proper"
pgrep -fl "$KANATA_BIN -c"          # one process on the brew path
```

> Using `$BREW_PREFIX/bin/kanata` (a symlink) means future `brew upgrade kanata` is picked up
> automatically with no plist edit — so when a fixed 1.12 *stable* ships, you just upgrade.

## Step 3 — Input Monitoring (usually already granted; verify)

macOS Input Monitoring (TCC) is keyed to the exact binary path. The brew path was almost certainly
granted before the prerelease detour, so switching back usually "just works". Verify: type into any
app — if remaps fire, you're fine. If keys pass through **raw** and the log shows
`TCC deny IOHIDDeviceOpen` / `not permitted`, a human must add `$KANATA_BIN` under
**System Settings → Privacy & Security → Input Monitoring** (⌘⇧G to type the path), toggle it ON,
then `sudo launchctl kickstart -k system/$DAEMON_LABEL`. (Cannot be scripted — TCC.db is SIP-protected.)

## Step 4 — disable the Karabiner-Elements grabber (keep the VirtualHIDDevice daemon!)

List the pqrs launchd jobs and disable **only** the grabber:

```bash
sudo launchctl list | grep -iE 'pqrs|karabiner'
# Expect three:
#   org.pqrs.Karabiner-DriverKit-VirtualHIDDevice-0x...   <- KEEP (kanata needs it)
#   org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon  <- KEEP (kanata needs it)
#   org.pqrs.service.daemon.karabiner_grabber            <- DISABLE (conflicts with kanata)

sudo launchctl bootout  system/org.pqrs.service.daemon.karabiner_grabber 2>/dev/null || true
sudo launchctl disable  system/org.pqrs.service.daemon.karabiner_grabber   # persists across reboot
pgrep -fl karabiner_grabber || echo "grabber down (good)"
pgrep -fl VirtualHIDDevice-Daemon >/dev/null && echo "VHID daemon up (good)"
```

> If the grabber respawns later, the durable fix is to remove **Karabiner-Elements** from Login
> Items / quit it. The standalone VirtualHIDDevice driver kanata needs is a *separate* package and
> is unaffected.

## Step 5 — install sleepwatcher + the wake LaunchDaemon

```bash
brew install sleepwatcher
SLEEPWATCHER="$BREW_PREFIX/sbin/sleepwatcher"      # /opt/homebrew/sbin or /usr/local/sbin
ls -l "$SLEEPWATCHER"
```

Create `/Library/LaunchDaemons/dev.kanata.wake.plist` (root). **Substitute your real
`$SLEEPWATCHER` path and your real `$HOME`** into the ProgramArguments below (launchd does not
expand variables — write absolute paths):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>dev.kanata.wake</string>
    <key>UserName</key><string>root</string>            <!-- root: must kickstart the root kanata daemon -->
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/sbin/sleepwatcher</string>   <!-- = $SLEEPWATCHER -->
        <string>-w</string>
        <string>/Users/CHANGEME/.local/bin/kanata-wake-restart.sh</string>  <!-- = $HOME/.local/bin/... -->
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>5</integer>
    <key>StandardOutPath</key><string>/var/log/kanata-wake.log</string>
    <key>StandardErrorPath</key><string>/var/log/kanata-wake.log</string>
</dict>
</plist>
```

Install + load it:

```bash
WAKE_PLIST=/Library/LaunchDaemons/dev.kanata.wake.plist
sudo chown root:wheel "$WAKE_PLIST" && sudo chmod 644 "$WAKE_PLIST"
sudo launchctl bootout system/dev.kanata.wake 2>/dev/null || true
sudo launchctl bootstrap system "$WAKE_PLIST"
pgrep -fl sleepwatcher    # should show it running -w .../kanata-wake-restart.sh
```

> If the wake script's `DAEMON_LABEL` (default `dev.kanata.kanata`) doesn't match your daemon's
> Label, edit the constant at the top of `~/.local/bin/kanata-wake-restart.sh` (and re-add to
> chezmoi with `chezmoi re-add ~/.local/bin/kanata-wake-restart.sh`).

## Step 6 — verify, then the real test

```bash
~/.local/bin/launch_kanata.sh status      # kanata + agent + wake daemon all loaded
tail -f /var/log/kanata-wake.log          # watch in one pane during the test
```

Real validation = **sleep, wake, confirm remaps still work with no manual restart**:

```bash
pmset sleepnow      # then WAKE WITH THE TRACKPAD, not a key (see note below)
```

After wake, `/var/log/kanata-wake.log` should show `try 1/3 … reached grab init, done`, and your
remaps (e.g. the caps-layer) should work immediately.

## Notes & gotchas

- **Wake with the trackpad/mouse, not a keypress.** Per #2008 the keyboard-keypress wake is the
  documented worst case (kanata tries to process the key before the driver recovered).
- **Single knob if it still wedges on wake:** raise `SETTLE=7` at the top of
  `~/.local/bin/kanata-wake-restart.sh` to `10` (then `chezmoi re-add` it).
- `--nodelay` / `--no-wait` are **not** sleep fixes — `--no-wait` only skips the "press enter"
  prompt, and `--nodelay` removes the startup settle delay we actually *want*. Don't add them.
- The wake script self-expires its lock (`/tmp/kanata-wake.lock`, stale after 45s) so a rapid
  sleep/wake loop can't deadlock it.
- When a fixed kanata **1.12 stable** lands in Homebrew, `brew upgrade kanata` picks it up via the
  symlink with no plist change; you could then keep or remove the wake daemon (harmless to keep).

References:
- [#2008 — 1.12 prerelease crashes on wake (regression from 1.11.0)](https://github.com/jtroo/kanata/issues/2008)
- [#1357 — sleep/lid crash; maintainer has no macOS device](https://github.com/jtroo/kanata/issues/1357)
- [Discussion #1537 — canonical Homebrew+launchctl setup; Karabiner-Elements grabber conflict](https://github.com/jtroo/kanata/discussions/1537)
