> **Updated 2026-07-22:** kanata is now Homebrew stable **1.12.0** (this doc predates that and says 1.11.0 / driver 6.2.0). It needs **BOTH Input Monitoring AND Accessibility** — Gotcha #3 below mentions only Input Monitoring. The `install_kanata_launchd.sh` installer referenced below is **retired**; current setup/recovery steps live in `~/.config/agent_context/kanata_state_2026-07-22.md`. The two-job architecture (root daemon + user agent, KeepAlive, no watchdogs) documented here is still current.

# kanata setup — reference doc for an agent

This documents how **kanata** (keyboard remapper) + **kanata-vk-agent** (app-aware
layer switching) are launched on this macOS machine, so a future agent can:

- **install fresh** on a brand-new macOS machine, or
- **recover** when a kanata / Karabiner / macOS update breaks the setup.

> This is the *current, working* design. It replaced an older `screen`+`sudo`
> launch (now deleted). If you find any `screen -dmS kanata_*`, a
> `launch_kanata_legacy.sh`, or a `com.user.launch-kanata` LaunchAgent on a
> machine, that's the OLD mechanism — tear it down (see "Migrating off the old setup").

---

## Architecture — what "working" looks like

| Component | Runs as | launchd job | Why |
|---|---|---|---|
| `kanata` | **root** | LaunchDaemon `/Library/LaunchDaemons/dev.kanata.kanata.plist` | macOS requires root to reach the Karabiner virtual-HID IPC under `…/org.pqrs/tmp/rootonly/`. A root LaunchDaemon means launchd starts it as root **with no interactive sudo password** and no `screen`. |
| `kanata-vk-agent` | **your user** | LaunchAgent `~/Library/LaunchAgents/dev.kanata.vk-agent.plist` | Needs GUI/WindowServer + Accessibility to detect the frontmost app. Does **not** need root — keep root off it. |

Both use `KeepAlive` so they restart on crash automatically. They talk over TCP
on `PORT` (the daemon listens with `-p PORT`; the agent connects with `-p PORT`).

### Files that make up the setup (all in `~/.local/bin/` unless noted)

| File | Role |
|---|---|
| `dev.kanata.kanata.plist` | Source copy of the **root daemon** plist. The installer copies it to `/Library/LaunchDaemons/`. |
| `~/Library/LaunchAgents/dev.kanata.vk-agent.plist` | The **user agent** plist (lives directly in LaunchAgents; no separate source copy). |
| `install_kanata_launchd.sh` | Idempotent one-shot installer: driver + brew pin + teardown + bootstrap both jobs. **Run from a normal terminal (it self-prompts for sudo), never with a leading `sudo`.** |
| `launch_kanata.sh` | Day-to-day control wrapper: `start \| stop \| restart \| status \| logs`. `restart` = fast reload after editing the `.kbd`. |
| `kanata_setup_doc.md` | This file. |

### Reference machine values (THIS machine — confirm per machine, don't blind-copy)

- `USER` = `maximegardoni`, `HOME` = `/Users/maximegardoni`, Apple Silicon → `HOMEBREW` = `/opt/homebrew`
- `KANATA_BIN` = `/opt/homebrew/bin/kanata`
- `VK_AGENT_BIN` = `/opt/homebrew/bin/kanata-vk-agent`
- `KBD_CONFIG` = `/Users/maximegardoni/.config/kanata/my_config.kbd`  (stable, chezmoi-managed; not in the ~/code/kanata git tree)
- `PORT` = `5829` (must match in BOTH plists)
- `TERM_BUNDLE_ID` = `net.kovidgoyal.kitty` (kitty — the app vk-agent does app-aware switching for, passed as `-b`)
- kanata `1.11.0` → pinned Karabiner driver `6.2.0`
- Daemon logs → `/var/log/kanata.log`; agent logs → `~/.local/log/kanata-vk-agent.log`

---

## ⚠️ Critical gotchas — read before touching anything

1. **The Karabiner driver version must MATCH the kanata version, not be "latest".**
   kanata bundles `karabiner-driverkit` built against ONE specific
   `Karabiner-DriverKit-VirtualHIDDevice` release's IPC. Installing a newer
   driver (or upgrading Karabiner-Elements) **breaks kanata**. For
   **kanata 1.11.0 the required driver is v6.2.0.** If `kanata --version`
   differs, look up the pinned version in
   <https://github.com/jtroo/kanata/blob/main/docs/setup-macos.md>
   (the "supported driver version is vX.Y.Z" line) and use that. After
   installing, **`brew pin karabiner-elements`** so a future `brew upgrade`
   can't pull a too-new driver. (The installer does the pin for you.)

2. **An agent cannot type a sudo password** in a non-interactive shell — `sudo`
   fails with *"a terminal is required to read the password"*. So **do not run
   the root steps yourself.** Stage all files (agent can do this), then hand the
   human the single command `~/.local/bin/install_kanata_launchd.sh` to run in
   their own terminal. The user-level LaunchAgent steps an agent *can* run.

3. **After a driver install / first daemon launch, kanata logs
   `IOHIDDeviceOpen error: (iokit/common) not permitted`** per keyboard. That's
   **Input Monitoring** not yet granted to the new daemon — expected, not a bug.
   Fix = **reboot** (needed anyway after a driver install). If still failing
   after reboot, grant Input Monitoring to the kanata binary (see Troubleshooting).

---

## Fresh install on a new machine

### Step 0 — discover machine-specific values (run, read the output)

```bash
echo "USER=$(id -un)  HOME=$HOME  UID=$(id -u)"
echo "HOMEBREW=$(brew --prefix)"                       # /opt/homebrew (Apple Si) or /usr/local (Intel)
which kanata kanata-vk-agent || echo "NOT INSTALLED YET"
kanata --version 2>/dev/null;  kanata-vk-agent --version 2>/dev/null
# Current driver version (empty if not installed):
plutil -extract CFBundleShortVersionString raw \
  "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/Info.plist" 2>/dev/null || echo "no driver"
# What's running / old mechanisms:
pgrep -fl kanata; screen -ls 2>/dev/null
ls ~/Library/LaunchAgents/ /Library/LaunchDaemons/ 2>/dev/null | grep -iE 'kanata'
launchctl list 2>/dev/null | grep -i kanata
# Bundle id of the terminal you want app-aware switching for:
osascript -e 'id of app "kitty"'
```

Then resolve each value listed under **Reference machine values** above for THIS
machine (username, brew prefix, config path, bundle id, driver version).

### Step 1 — install binaries (if missing)

```bash
brew install kanata
brew tap devsunb/tap && brew install kanata-vk-agent
mkdir -p ~/.local/log
```
The driver itself is installed by the installer in Step 3 (don't install it by hand).

### Step 2 — stage the plists + installer (agent does this; no sudo)

Create the three files with the resolved values. Templates (substitute your values):

`~/.local/bin/dev.kanata.kanata.plist` (root daemon):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>dev.kanata.kanata</string>
  <key>UserName</key><string>root</string>
  <key>ProgramArguments</key><array>
    <string>KANATA_BIN</string>
    <string>-c</string><string>KBD_CONFIG</string>
    <string>-p</string><string>PORT</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ThrottleInterval</key><integer>5</integer>
  <key>StandardOutPath</key><string>/var/log/kanata.log</string>
  <key>StandardErrorPath</key><string>/var/log/kanata.log</string>
</dict></plist>
```

`~/Library/LaunchAgents/dev.kanata.vk-agent.plist` (user agent):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>dev.kanata.vk-agent</string>
  <key>ProgramArguments</key><array>
    <string>VK_AGENT_BIN</string>
    <string>-p</string><string>PORT</string>
    <string>-b</string><string>TERM_BUNDLE_ID</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>3</integer>
  <key>StandardOutPath</key><string>HOME/.local/log/kanata-vk-agent.log</string>
  <key>StandardErrorPath</key><string>HOME/.local/log/kanata-vk-agent.log</string>
</dict></plist>
```

`install_kanata_launchd.sh` is `$HOME`-generic and only hardcodes `DRIVER_VER`.
Copy the existing one and **edit `DRIVER_VER`** if the kanata version changed.
Its only machine-specific dependency is the daemon plist it copies
(`~/.local/bin/dev.kanata.kanata.plist`) — so the per-machine paths live in that
plist, not in the installer.

### Step 3 — run the installer (HUMAN, in their own terminal)

```bash
~/.local/bin/install_kanata_launchd.sh        # NO leading sudo; it self-prompts
```
It will: install+activate the pinned driver → `brew pin karabiner-elements` →
tear down old screen/manual kanata → bootstrap the root daemon → bootstrap the
user agent. Approve any System Settings prompt (driver / Input Monitoring).
**Reboot** if the driver was upgraded.

### Step 4 — verify

```bash
~/.local/bin/launch_kanata.sh status      # both jobs state = running
~/.local/bin/launch_kanata.sh logs        # check for errors
```
In `/var/log/kanata.log` you want `driver version matched: true` and **no**
lingering `IOHIDDeviceOpen … not permitted`. Then test a remapped key.

---

## Day-to-day control

```bash
~/.local/bin/launch_kanata.sh start     # bootstrap + start both jobs
~/.local/bin/launch_kanata.sh stop      # stop both (daemon needs sudo)
~/.local/bin/launch_kanata.sh restart   # fast reload after editing the .kbd
~/.local/bin/launch_kanata.sh status
~/.local/bin/launch_kanata.sh logs
```
After editing `my_config.kbd`, `restart` is the fast path to reload it.

---

## Troubleshooting — "it broke"

**First, find which layer broke:** `~/.local/bin/launch_kanata.sh status` + `logs`.

- **`IOHIDDeviceOpen … not permitted` in `/var/log/kanata.log`** → Input
  Monitoring missing for the daemon. Reboot first. If still failing: System
  Settings → Privacy & Security → **Input Monitoring**, ensure
  `$(brew --prefix)/bin/kanata` is listed and enabled (add via `+`, ⌘⇧G → the
  bin dir if missing), then `launch_kanata.sh restart`.

- **kanata exits immediately / `driver version matched: false` / connection
  errors to the virtual HID** → driver/kanata version mismatch (Gotcha #1).
  This is the **most likely cause after a `brew upgrade`**. Check:
  ```bash
  kanata --version
  plutil -extract CFBundleShortVersionString raw \
    "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/Info.plist"
  ```
  Look up the required driver for the new kanata version in the setup-macos.md
  link (Gotcha #1), set `DRIVER_VER` in `install_kanata_launchd.sh`, re-run the
  installer (HUMAN), reboot. Re-confirm `brew pin karabiner-elements` held.

- **Remaps work but app-aware switching doesn't** → the agent, not the daemon.
  Check `~/.local/log/kanata-vk-agent.log`. Ensure the agent has **Accessibility**
  permission, that `-b` has the right bundle id (`osascript -e 'id of app "…"'`),
  and that `-p` matches the daemon's port. `launchctl kickstart -k gui/$(id -u)/dev.kanata.vk-agent`.

- **Config typo** → kanata refuses to load and `KeepAlive` will crash-loop it
  (throttled 5s). The error is in `/var/log/kanata.log`. Fix the `.kbd`, `restart`.

- **Nuke & repave** → the installer is idempotent; re-running it re-bootstraps
  both jobs cleanly. To fully reset a job:
  `sudo launchctl bootout system/dev.kanata.kanata` /
  `launchctl bootout gui/$(id -u)/dev.kanata.vk-agent`, then `start`.

---

## Migrating off the old (screen+sudo) setup

If a machine still has the legacy mechanism, remove every trace before/while installing:

```bash
# Old detached screen sessions:
screen -S kanata_main -X quit     2>/dev/null || true
screen -S kanata_vk_agent -X quit 2>/dev/null || true
# Old user LaunchAgent that ran the legacy script (no sudo):
launchctl bootout gui/$(id -u)/com.user.launch-kanata 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.user.launch-kanata.plist
rm -f ~/.local/bin/launch_kanata_legacy.sh
# Old kanata processes (the installer's teardown also does this; root needs sudo):
pkill -f 'kanata-vk-agent' 2>/dev/null || true
sudo pkill -f "$(brew --prefix)/bin/kanata" 2>/dev/null || true   # HUMAN/sudo
```
Also check Login Items, `crontab -l`, and `~/.zprofile`/`~/.zshrc` for any
`launch_kanata` autostart. Then proceed with the fresh-install steps above.
The installer's teardown stage kills the running processes atomically right
before bootstrapping the daemon, so there's no dead-keyboard window — prefer
letting it do the process teardown rather than killing kanata by hand first.
