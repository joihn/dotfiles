# Runbook: move kanata to 1.12.0-prerelease-2 to fix the macOS sleep/wake bug

> ⚠️ **SUPERSEDED (2026-06-17) — DO NOT FOLLOW THIS RUNBOOK.** The 1.12.0-prerelease approach
> below did **not** hold up: that prerelease is a macOS regression that crashes/wedges on wake
> (upstream issue #2008), and 1.11.0 stable does not have that bug. The current, working approach
> is **brew-stable kanata + a sleepwatcher restart-on-wake daemon + disabling the Karabiner-Elements
> grabber**. Use **`kanata_post_sleep_recovery.md`** instead. This file is kept only for history
> and for the still-useful Input-Monitoring / binary-variant / launchd notes.

**Audience:** an AI agent (or human) setting up a *second* macOS machine the same way the
first one was done on 2026-06-15.

## Why we do this

On macOS, kanata outputs remapped keys through the **Karabiner-DriverKit-VirtualHIDDevice**.
When the machine sleeps/wakes, that DriverKit virtual keyboard is torn down and re-created.
On **stable 1.11.0**, kanata keeps running but its output sink is now dead and it does **not**
auto-reconnect → the keyboard "misbehaves" (keys unmapped / dead) until kanata is restarted
manually.

The fix is kanata PR **#2013** ("drop key writes when DriverKit sink is disconnected"): it treats
the disconnect as non-fatal and reconnects via the event loop's `output_ready()` polling. It first
shipped in **v1.12.0-prerelease-2** (published ~12 Apr 2026), alongside #2015 (clean shutdown +
startup diagnostics) and #2016 (release keyboard grab on lock screen / user switch).

References:
- Issue (crash on wake, fixed): https://github.com/jtroo/kanata/issues/2008
- Fix PR: https://github.com/jtroo/kanata/pull/2013
- Releases: https://github.com/jtroo/kanata/releases

## ⚠️ FIRST: check whether you even need the prerelease

By the time you run this, **1.12.0 (or newer) may be stable in Homebrew**. If so, skip the whole
manual-binary dance and just upgrade:

```bash
brew update && brew info kanata        # is stable now >= 1.12.0 ?
# if yes:
brew upgrade kanata
sudo launchctl kickstart -k system/dev.kanata.kanata   # adjust label if different
# brew keeps the same /opt/homebrew/bin/kanata path, so Input Monitoring usually stays granted.
```

`brew upgrade` keeps the same `/opt/homebrew/bin/kanata` path, so Input Monitoring usually stays
granted and you're done. Only continue with the manual steps below if stable is still < 1.12.0.

## The single biggest gotcha (do not skip)

macOS **Input Monitoring** (TCC `kTCCServiceListenEvent`) permission is keyed to the *specific
binary path + code signature*. Pointing the daemon at a **new binary path** means the new binary
has **no** Input Monitoring grant. Because kanata runs as a **root** LaunchDaemon (UID 0), macOS
**cannot show the permission prompt** — it just silently denies, and you'll see in the log:

```
IOHIDDeviceOpen error: (iokit/common) not permitted Apple Internal Keyboard / Trackpad
[com.apple.iohid:default] TCC deny IOHIDDeviceOpen
tccd: notifyUserOfDeniedAccessBy: for <binary> fails when requestor has UID 0
```

Symptom: kanata logs `keyboard grabbed` but typing is NOT remapped (keys pass through raw).
**Fix = manually add the new binary to Input Monitoring (Step 5).** This is mandatory whenever the
binary path changes.

---

## Discover this machine's specifics first

Do not assume the values from the first machine. Find them:

```bash
uname -m                                   # arm64 (Apple Silicon) or x86_64 (Intel)
which kanata && kanata --version           # current version & path
ls -l /Library/LaunchDaemons/ | grep -i kanata    # daemon plist filename / label
# read the plist to get: Label, ProgramArguments (binary path, -c config path, -p port), log paths
cat /Library/LaunchDaemons/dev.kanata.kanata.plist
# does the config actually USE cmd actions? (commented-out ;; lines do NOT count)
grep -nE '\(cmd\b|danger-enable-cmd' <your_config.kbd>
```

First machine's values (for reference — the second machine may differ):
- arch: `arm64`
- config: `/Users/maximegardoni/code/kanata/cfg_samples/my_config.kbd`
- daemon plist: `/Library/LaunchDaemons/dev.kanata.kanata.plist`, label `dev.kanata.kanata`,
  runs as **root**, port `5829`, logs to `/var/log/kanata.log`
- there is also a user LaunchAgent `dev.kanata.vk-agent` (auto-reconnects; no action needed)
- helper script: `~/.local/bin/launch_kanata.sh {start|stop|restart|status|logs}`
- config has `danger-enable-cmd yes` but **no active cmd action** (the only `cmd` line is
  commented out with `;;`) → the **standard** binary is correct, NOT the `cmd_allowed` one.

### Which binary variant?

The release zip contains two binaries:
- `kanata_macos_<arch>`              → standard (cmd compiled out) — **use this by default**
- `kanata_macos_cmd_allowed_<arch>`  → only if the config has a **live** `(cmd ...)` action

Standard binary still parses `danger-enable-cmd yes` fine; it just logs
`NOTE: kanata was compiled to never allow cmd`. That's harmless.

---

## Step 1 — download & extract the prerelease binary

Pick the asset for the arch: `macos-binaries-arm64.zip` or `macos-binaries-x64.zip`.

```bash
cd "$(mktemp -d)"
ARCH=arm64   # or x64 on Intel
curl -fL --retry 2 -o k.zip \
  "https://github.com/jtroo/kanata/releases/download/v1.12.0-prerelease-2/macos-binaries-${ARCH}.zip"
unzip k.zip -d k
ls -l k/                       # kanata_macos_<arch> and kanata_macos_cmd_allowed_<arch>
BIN="$PWD/k/kanata_macos_${ARCH}"   # standard variant (default)
file "$BIN"                    # confirm: Mach-O 64-bit executable <arch>
```

## Step 2 — verify it runs and the config is valid

```bash
xattr -dr com.apple.quarantine "$BIN" 2>/dev/null   # clear Gatekeeper quarantine
"$BIN" --version                                    # expect: kanata 1.12.0-prerelease-2
"$BIN" -c <your_config.kbd> --check                 # expect: "config file is valid"
```

## Step 3 — install to a pinned, brew-upgrade-proof path

We install to `/usr/local/bin/kanata-1.12.0-pre2` (root-owned) so `brew upgrade` never touches it,
and the existing brew binary stays as a fallback.

```bash
sudo install -m 755 -o root -g wheel "$BIN" /usr/local/bin/kanata-1.12.0-pre2
sudo xattr -dr com.apple.quarantine /usr/local/bin/kanata-1.12.0-pre2 2>/dev/null
```

## Step 4 — repoint the LaunchDaemon plist & reload

Back up the plist, then change ONLY the first `ProgramArguments` string (the binary path) to
`/usr/local/bin/kanata-1.12.0-pre2`; leave config path, port, KeepAlive, log paths unchanged.

```bash
PLIST=/Library/LaunchDaemons/dev.kanata.kanata.plist     # adjust if different
sudo cp "$PLIST" "${PLIST}.bak-$(kanata --version | awk '{print $2}')"   # e.g. .bak-1.11.0
# edit $PLIST: ProgramArguments[0] -> /usr/local/bin/kanata-1.12.0-pre2

# Because the plist CHANGED, a plain `kickstart` is NOT enough (it re-runs the OLD definition).
# You must bootout + bootstrap so launchd reloads the new path:
sudo launchctl bootout system/dev.kanata.kanata 2>/dev/null || true
sudo launchctl enable system/dev.kanata.kanata
sudo launchctl bootstrap system "$PLIST"
sudo launchctl print system/dev.kanata.kanata | grep -E 'state|pid|program'
# expect: state = running, program = /usr/local/bin/kanata-1.12.0-pre2, a pid
```

> Note: if `bootstrap` returns `5: Input/output error`, the old job hadn't fully exited. Just
> re-run the `bootout … || true; enable; bootstrap` block once more — it succeeds once the old
> process is gone. (This happened on machine #1.)

## Step 5 — grant Input Monitoring to the new binary (MANDATORY)

At this point the daemon is "running" but **rebinds won't work yet** — see "biggest gotcha" above.

1. **System Settings → Privacy & Security → Input Monitoring**
2. Click **`+`**, press **⌘ + Shift + G**, enter `/usr/local/bin/kanata-1.12.0-pre2`, Open
3. Ensure its toggle is **ON** (keep existing kanata/Karabiner entries on too)
4. Restart the daemon (plist unchanged now, so a kickstart is fine):
   ```bash
   sudo launchctl kickstart -k system/dev.kanata.kanata
   ```

(A human must do the GUI grant — it cannot be scripted; the system TCC.db is SIP-protected.)

## Step 6 — verify success

```bash
# log is world-readable (root:wheel 644). grep -a because of ANSI color bytes.
tail -n 200 /var/log/kanata.log | sed -E 's/\x1b\[[0-9;]*m//g' \
  | grep -aiE 'starting|grabbed|TCC deny|not permitted|virtual_hid_keyboard_ready' | tail
```
Success looks like:
- `kanata v1.12.0-prerelease-2 starting`
- `keyboard grabbed, entering event processing loop`
- **NO** `TCC deny IOHIDDeviceOpen` and **NO** `not permitted` lines
- `virtual_hid_keyboard_ready true`

Then physically test a remap. Real validation = sleep the machine, wake it, confirm rebinds still
work without a manual restart.

## Rollback (back to stable brew 1.11.0)

```bash
sudo cp /Library/LaunchDaemons/dev.kanata.kanata.plist.bak-1.11.0 \
        /Library/LaunchDaemons/dev.kanata.kanata.plist
sudo launchctl bootout system/dev.kanata.kanata 2>/dev/null || true
sudo launchctl bootstrap system /Library/LaunchDaemons/dev.kanata.kanata.plist
```
The brew binary at `/opt/homebrew/bin/kanata` was never modified. (On Intel it's
`/usr/local/bin/kanata` instead — adjust.)

## Minor note

1.12.0-pre2 logs `virtual_hid_keyboard_ready true` very frequently (the new readiness polling),
which grows `/var/log/kanata.log` faster than 1.11.0. Harmless; can be quieted later via kanata's
log-level options if desired.
