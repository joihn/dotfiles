# Runbook: kanata on macOS via a source build of `main` (dual TCC permission)

**Audience:** an AI agent (Claude Code) or human bringing a *second* macOS machine to the same
working state as machine #1, set up on **2026-06-18**.

> **This SUPERSEDES `kanata_post_sleep_recovery.md` for the binary choice.** That runbook put you on
> brew-stable **1.11.0** + a sleepwatcher restart-on-wake hook. We have since moved to a **source
> build of `jtroo/kanata` `main`** because 1.11.0 has *no* post-wake recovery code at all, while
> `main` (post-`v1.12.0-prerelease-2`) carries the macOS wake fixes that actually matter:
> - **#2041** (`0a5bc3e`, merged 2026-05-02): crash-safe restart while typing — fixes the
>   channel-overflow freeze and stuck-keys-after-restart. This is the keypress-on-wake worst case.
> - DriverKit **output-sink auto-recovery** (#2013/#1950/#1964): on wake, kanata releases input so
>   the keyboard works as plain macOS, then re-grabs when the sink returns — instead of silently
>   dying like 1.11.0.
> - Clearer startup diagnostics + pre-flight permission registration (#2015/#2027/#2032/#2036).
>
> The old fixed-`SETTLE` sleepwatcher hook is kept only as a harmless full-wake **backstop**.

## What "done" looks like (same as machine #1)

1. kanata daemon runs a **source build of `main`** pinned at commit **`40a8b17`** (2026-06-16),
   installed at **`/usr/local/bin/kanata-main-40a8b17`** (Apple Silicon). The brew 1.11.0 binary at
   `/opt/homebrew/bin/kanata` stays as an instant rollback.
2. The binary has **BOTH** macOS permissions granted: **Input Monitoring** *and* **Accessibility**
   (the `main` build needs both — 1.11.0 only needed Input Monitoring; this is the #1 gotcha).
3. The Karabiner-Elements **grabber** is disabled (conflicts with kanata); the Karabiner
   **VirtualHIDDevice daemon** kanata requires stays running.
4. **Two** recovery daemons stay loaded: `dev.kanata.wake` (sleepwatcher, fast full-wake path) and
   `dev.kanata.wake-watchdog` (catches DarkWake/scheduled wakes that sleepwatcher misses — issue
   #2094). See Step 7.

---

## Step 0 — discover THIS machine's specifics (don't copy machine #1's blindly)

```bash
uname -m                                            # arm64 -> /opt/homebrew ; x86_64 -> /usr/local
whoami; echo "$HOME"
which -a kanata; brew --prefix
ls -l /Library/LaunchDaemons/ | grep -i kanata
cat /Library/LaunchDaemons/dev.kanata.kanata.plist  # note Label, -c config, -p port, log paths
pgrep -fl 'kanata|sleepwatcher|karabiner_grabber|VirtualHIDDevice-Daemon'
which cargo rustc || echo "need rust toolchain (rustup)"
```

Helpers used below (adjust to the discovered values):

```bash
BREW_PREFIX="$(brew --prefix)"            # /opt/homebrew (arm64) or /usr/local (intel)
DAEMON_LABEL="dev.kanata.kanata"
PIN=40a8b17                               # source commit to build (bump intentionally, not by accident)
NEWBIN="/usr/local/bin/kanata-main-${PIN}"
CONFIG="$HOME/.config/kanata/my_config.kbd"   # the daemon's -c path (stable, chezmoi-managed)
```

> **sudo:** several steps need root. If you are an agent and hit a blocked-sudo message, ask the
> user to run `sudo -v` in a terminal and say "done".

## Step 1 — pull dotfiles (gets the config, scripts, and this runbook)

chezmoi carries the **config itself** (`~/.config/kanata/my_config.kbd`), the wake hook
(`~/.local/bin/kanata-wake-restart.sh`), `launch_kanata.sh`, and the agent_context runbooks. The
config is delivered by **chezmoi**, NOT by a git branch (machine #1's `better_no_cmd_issue` branch
is local-only and cannot be pushed to the upstream remote).

```bash
chezmoi update
test -f "$CONFIG" && echo "config present" || echo "MISSING — run: chezmoi apply"
ls -l ~/.local/bin/kanata-wake-restart.sh   # should exist, +x
```

> **Config location:** the daemon reads `~/.config/kanata/my_config.kbd` — a *stable* path owned by
> chezmoi (history via the joihn/dotfiles repo). It is deliberately NOT inside the `~/code/kanata`
> git working tree, so kanata-repo branch switches can never make the live config vanish. Edit the
> config there directly; the old `~/code/kanata/cfg_samples/my_config.kbd` is no longer used by the
> daemon and is no longer chezmoi-managed.

## Step 2 — build the binary from `main` (isolated worktree, no branch switching)

The macOS build is the **standard** binary: the config has `danger-enable-cmd no` and no live
`(cmd ...)` action, so do **NOT** use `--features cmd`. Default features include `tcp_server`, so
the `-p` port works with no extra flags.

```bash
cd "$HOME/code/kanata"
git fetch origin
# Build in a throwaway worktree pinned at $PIN so the user's working branch/config is untouched:
git worktree add /tmp/kanata-build "$PIN"
( cd /tmp/kanata-build && cargo build --release )      # ~30s + cached deps
/tmp/kanata-build/target/release/kanata --version       # expect: kanata 1.12.0-prerelease-2
/tmp/kanata-build/target/release/kanata -c "$CONFIG" --check   # expect: "config file is valid"
```

> If `~/code/kanata` doesn't exist: `git clone https://github.com/jtroo/kanata.git ~/code/kanata`
> first, then `chezmoi apply` to lay down the config, then build.

## Step 3 — install the binary to the pinned path

```bash
sudo install -m 755 -o root -g wheel /tmp/kanata-build/target/release/kanata "$NEWBIN"
sudo xattr -dr com.apple.quarantine "$NEWBIN" 2>/dev/null || true
"$NEWBIN" --version
cd "$HOME/code/kanata" && git worktree remove /tmp/kanata-build   # clean up
```

## Step 4 — point the LaunchDaemon at the new binary & reload

Edit `/Library/LaunchDaemons/dev.kanata.kanata.plist` so `ProgramArguments[0]` is `$NEWBIN`; keep
`-c $CONFIG`, `-p <port>` (machine #1 uses 5829), `UserName=root`, `KeepAlive={SuccessfulExit:false}`,
`ThrottleInterval=5`, log paths. Full reference (Apple Silicon):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>dev.kanata.kanata</string>
    <key>UserName</key><string>root</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/kanata-main-40a8b17</string>   <!-- = $NEWBIN -->
        <string>-c</string>
        <string>/Users/CHANGEME/.config/kanata/my_config.kbd</string>  <!-- = $CONFIG -->
        <string>-p</string>
        <string>5829</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>ThrottleInterval</key><integer>5</integer>
    <key>StandardOutPath</key><string>/var/log/kanata.log</string>
    <key>StandardErrorPath</key><string>/var/log/kanata.log</string>
</dict>
</plist>
```

```bash
PLIST=/Library/LaunchDaemons/dev.kanata.kanata.plist
sudo cp "$PLIST" "${PLIST}.bak-$(date +%Y%m%d-%H%M%S)"
# ...edit binary path in $PLIST (or write the file above)...
sudo launchctl bootout system/$DAEMON_LABEL 2>/dev/null || true
sleep 1
sudo launchctl bootstrap system "$PLIST"
```

Until BOTH permissions (Step 5) are granted, kanata will **crash-loop** (start → permission error →
exit → KeepAlive restart every ~5s). That's expected and harmless.

## Step 5 — grant BOTH Input Monitoring AND Accessibility (MANDATORY, manual — the #1 gotcha)

TCC is keyed to the exact binary path and is SIP-protected, so this **cannot be scripted**, and a
**new binary path has no grants**. The `main` build pre-registers itself in both panes on first run
(#2027/#2036), so usually the entries already exist and just need toggling **ON**:

1. **System Settings → Privacy & Security → Input Monitoring** → enable `kanata-main-<PIN>`
   (or add via `+`, ⌘⇧G, type `$NEWBIN`).
2. **System Settings → Privacy & Security → Accessibility** → enable the same binary. *This second
   permission is new vs 1.11.0 and is the commonly-missed one (issue #1211).* Open it directly with:
   `open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"`
3. Then: `sudo launchctl kickstart -k system/$DAEMON_LABEL`

Success in `/var/log/kanata.log` (strip ANSI: `sed -E 's/\x1b\[[0-9;]*m//g'`):
`driver version matched: true` → `driver connected: true` → `Starting kanata proper` →
`cleared stale virtual HID keyboard state` → **`keyboard grabbed, entering event processing loop`**,
and **no** `not permitted` / `needs macOS ... permission` / `failed to open keyboard`. Then type and
confirm remaps fire.

> If you see `driver version matched: false`, the installed Karabiner-DriverKit-VirtualHIDDevice is
> too old for `main` (it pins `karabiner-driverkit 0.3.1`) — upgrade the standalone VHID driver.

## Step 6 — disable the Karabiner-Elements grabber (keep the VHID daemon!)

```bash
sudo launchctl list | grep -iE 'pqrs|karabiner'
sudo launchctl bootout system/org.pqrs.service.daemon.karabiner_grabber 2>/dev/null || true
sudo launchctl disable system/org.pqrs.service.daemon.karabiner_grabber   # persists across reboot
pgrep -fl karabiner_grabber || echo "grabber down (good)"
pgrep -fl VirtualHIDDevice-Daemon >/dev/null && echo "VHID daemon up (good)"
```

## Step 7 — THREE recovery layers: sleepwatcher hook + wake WATCHDOG + vk-agent log TRIGGER

Real-world finding (2026-06-19, issue **#2094**): `main` recovers the DriverKit **output sink** on
wake, but the keyboard **input grab** can still silently die on a **DarkWake / scheduled-alarm wake**
(e.g. a `calaccessd` calendar alarm) — kanata logs nothing, the output/TCP path stays alive, and it
sits grabbed-but-deaf until kickstarted. sleepwatcher's `-w` only fires on **full** wakes, so it
misses exactly these.

Second real-world finding (2026-06-22): the grab/socket can also die with **no system sleep at all**
— a display-wake, a power-adapter attach, or virtual-HID churn (`IOHIDLibUserClient` open/close on
the Karabiner keyboard) is enough. `pmset` shows no `Wake`/`DarkWake`, so **neither** the sleepwatcher
hook **nor** the watchdog fires; both are wake-event-based. The only distinctive signal is in the
vk-agent log (`failed to write message to kanata: Broken pipe`). Hence a third, symptom-based layer.

All three are installed on machine #1 as of 2026-06-22. The three layers:

**7a. sleepwatcher hook (fast path, full wakes).** Install per `kanata_post_sleep_recovery.md`
Step 5 (`brew install sleepwatcher`; create `/Library/LaunchDaemons/dev.kanata.wake.plist` with your
real `$SLEEPWATCHER` + `$HOME` paths; bootstrap it). Runs `~/.local/bin/kanata-wake-restart.sh`
(arrives via chezmoi). No `SETTLE` tuning.

**7b. wake watchdog (closes the DarkWake gap).** `~/.local/bin/kanata-wake-watchdog.sh` (chezmoi)
runs on a launchd `StartInterval` and kickstarts kanata whenever the most-recent wake (full **or**
DarkWake, from `pmset -g log`) is newer than the kanata process start — i.e. re-grab after *any*
wake, self-deduping. It calls `kanata-wake-restart.sh` (shared self-expiring lock dedupes against
sleepwatcher). launchd defers `StartInterval` while asleep → ~no battery cost. Install:

```xml
<!-- /Library/LaunchDaemons/dev.kanata.wake-watchdog.plist  (root) -->
<dict>
    <key>Label</key><string>dev.kanata.wake-watchdog</string>
    <key>UserName</key><string>root</string>
    <key>ProgramArguments</key>
    <array><string>/Users/CHANGEME/.local/bin/kanata-wake-watchdog.sh</string></array>  <!-- $HOME -->
    <key>StartInterval</key><integer>15</integer>
    <key>RunAtLoad</key><true/>
    <key>StandardOutPath</key><string>/var/log/kanata-wake.log</string>
    <key>StandardErrorPath</key><string>/var/log/kanata-wake.log</string>
</dict>
```
```bash
WP=/Library/LaunchDaemons/dev.kanata.wake-watchdog.plist
sudo chown root:wheel "$WP" && sudo chmod 644 "$WP"
sudo launchctl bootout system/dev.kanata.wake-watchdog 2>/dev/null || true
sudo launchctl bootstrap system "$WP"
```
(`launchctl print system/dev.kanata.wake-watchdog` shows `state = not running` between its 15s
ticks — that is correct for a `StartInterval` job; check `runs =` climbs and `last exit code = 0`.)

**7c. vk-agent log trigger (closes the NON-wake gap).** `~/.local/bin/kanata-vkagent-log-trigger.sh`
(chezmoi) tails the vk-agent log and, on the `Broken pipe` / `failed to write message to kanata` line
(and ONLY that line — never the `failed to connect within 2 seconds` panic, which fires after every
kickstart and would loop), calls `kanata-wake-restart.sh`. Feedback-loop guard is stateless: it
ignores any match while the kanata daemon process is younger than `COOLDOWN` (45s) — our own kickstart
kills the socket and produces another broken pipe, but the just-restarted daemon's small age skips it.
Root (kickstart needs root); `KeepAlive` so the long-running `tail -F` self-heals on log rotation.
Caveat: a broken pipe doesn't *prove* the grab died, so this can occasionally do a ~4s restart on a
transient socket blip. Install:

```xml
<!-- /Library/LaunchDaemons/dev.kanata.vkagent-trigger.plist  (root) -->
<dict>
    <key>Label</key><string>dev.kanata.vkagent-trigger</string>
    <key>UserName</key><string>root</string>
    <key>ProgramArguments</key>
    <array><string>/Users/CHANGEME/.local/bin/kanata-vkagent-log-trigger.sh</string></array>  <!-- $HOME -->
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>StandardOutPath</key><string>/var/log/kanata-wake.log</string>
    <key>StandardErrorPath</key><string>/var/log/kanata-wake.log</string>
</dict>
```
```bash
TP=/Library/LaunchDaemons/dev.kanata.vkagent-trigger.plist
sudo chown root:wheel "$TP" && sudo chmod 644 "$TP"
sudo launchctl bootout system/dev.kanata.vkagent-trigger 2>/dev/null || true
sudo launchctl bootstrap system "$TP"
```

## Step 8 — verify, then the real test

```bash
~/.local/bin/launch_kanata.sh status      # daemon on $NEWBIN, wake daemon loaded
# All four jobs should be present (kanata + the 3 recovery layers):
for L in dev.kanata.kanata dev.kanata.wake dev.kanata.wake-watchdog dev.kanata.vkagent-trigger; do
  echo "$L: $(sudo launchctl print system/$L 2>/dev/null | awk -F'= ' '/state =/{print $2; exit}')"
done
# Unattended sleep/wake cycle (timer wake; software can't wake the Mac otherwise):
sudo pmset relative wake 35 && pmset sleepnow
```

After wake: remaps must work with **no manual kickstart**. Repeat once **waking with a keypress**
(validates #2041). Watch `/var/log/kanata.log`.

Test the 7c trigger without a sleep cycle — inject the signal line into the vk-agent log and confirm
a re-grab fires in `/var/log/kanata-wake.log` (this WILL kickstart kanata, ~4s):
```bash
echo "$(date '+%H:%M:%S') [ERROR] failed to write message to kanata: Broken pipe (os error 32)" \
  >> ~/.local/log/kanata-vk-agent.log
sleep 12 && tail -n 5 /var/log/kanata-wake.log   # expect: vkagent-trigger ... triggering re-grab
```

## Notes & gotchas

- **Dual permission** (Input Monitoring + Accessibility) is the single biggest difference from the
  1.11.0 setup. A missing Accessibility grant looks like a grab failure / `not permitted` (#1211).
- **Rollback** to brew 1.11.0: restore a `dev.kanata.kanata.plist.bak-*` (it points at
  `$BREW_PREFIX/bin/kanata`) and `bootout`/`bootstrap`. The brew binary is never modified.
- **Deferred patch for #2093** (apply ONLY if observed): on `main`, a wake can occasionally leave
  the DriverKit output sink unable to reconnect — log sticks on
  `Waiting for the output backend and console session to recover...` (`connect_failed
  asio.system:17`) and the keyboard stays vanilla until `kickstart -k`. This is a sink-reconnect
  race, **more likely with multiple kanata instances** (machine #1 runs one, so we did NOT patch).
  If it bites: bound the recovery wait in `src/kanata/macos.rs` (the `loop` ~line 243 that waits for
  `sink_ready && session_ready`) — track a `wedge_since: Instant` only when `session_ready &&
  !sink_ready`, and `bail!` after ~10s so KeepAlive (`SuccessfulExit:false`) restarts with a fresh
  client. Add `--no-wait` to the plist ProgramArguments so the error-exit can't block on the
  "Press enter to exit" prompt. Consider upstreaming as the maintainer's suggested fix #1.

References:
- #2041 crash-safe restart while typing: https://github.com/jtroo/kanata/pull/2041
- #2093 post-wake sink-reconnect hang (open): https://github.com/jtroo/kanata/issues/2093
- #1211 the missing-Accessibility "(iokit/common) not permitted": https://github.com/jtroo/kanata/issues/1211
- #1357 sleep/lid crash; maintainer has no macOS device: https://github.com/jtroo/kanata/issues/1357
