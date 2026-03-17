# termavatar — Development Guide

## What is this project?
A macOS tool that attaches floating circular avatar photos to terminal windows. Designed for people running multiple AI coding agents (Claude Code) who need to visually identify each terminal at a glance.

**GitHub**: https://github.com/zhengyue8/termavatar
**Author**: Yue (lucky888)

## Architecture

Three components:

1. **CLI** (`termavatar`) — Bash script for add/remove/list/watch/unwatch commands
2. **Watcher** (`termavatar-watcher`, `Sources/Watcher.swift`) — Swift daemon that polls Accessibility API every 2s, spawns/kills overlay processes
3. **Overlay** (`termavatar-overlay`, `Sources/Overlay.swift`) — Swift app that creates a floating NSWindow with circular avatar

### Overlay internals (Sources/Overlay.swift)
- `WindowState` enum: `.visible(frame)`, `.minimized`, `.notFound`
- `MinimizedDock` struct: coordinates parked avatar positions via `~/.termavatar/dock/` slot files; prefers secondary monitor
- `NotifySignal` struct: file-based notification via `~/.termavatar/notify/<keyword>`
- `WindowTracker` class: uses Accessibility API to find windows, stores `matchedAXWindow` (AXUIElement) and `matchedAppPID` for targeted un-minimize
- `DraggableView` class: NSView subclass with mouseDown/mouseDragged/mouseUp; 3px threshold to distinguish click vs drag
- `OverlayApp` class: NSApplicationDelegate, builds the window, runs 10fps tracking timer

### Key technical decisions
- **Z-ordering**: `window.order(.above, relativeTo: Int(targetCGWindowID))` with `.normal` level — avatar floats above its terminal but hides behind other apps
- **Minimize detection**: `kAXMinimizedAttribute` via Accessibility API
- **Un-minimize specific window**: `AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute, false)` + `AXUIElementPerformAction(axWin, kAXRaiseAction)` — this raises the exact matched window, not just activates the app
- **Parked state**: `.floating` level when terminal is minimized, `.normal` when visible
- **Drag memory**: `userParkedPosition` saved on drag, reused on re-minimize
- **Notification**: file-based signaling; overlay checks every 1 second (tickCount % 10 at 10fps); plays `NSSound(named: "Glass")` on first detection; red dot 12px with 1.5px white border and pulse animation
- **Coordinate conversion**: macOS uses bottom-left origin (NS) vs top-left (CG); formula: `nsTargetY = screenH - targetFrame.origin.y - targetFrame.height`

## Config format
`~/.termavatar/config` — pipe-delimited:
```
keyword|display_name|image_path|corner|size
```

## Notification hook (Claude Code integration)
- `notify-avatar.sh` — called by Claude Code's Notification hook
- Walks process tree to find terminal PID
- Gets ONLY `window 1` (frontmost) title via osascript — critical for correct targeting when terminal app has multiple windows
- Matches title against config keywords, touches `~/.termavatar/notify/<keyword>`
- Claude Code settings: `~/.claude/settings.json` hooks > Notification

## Agent-avatar (local dev version)
- `/Users/lucky888/agent-avatar/` — the live working version with Jack, Show, Dr. King
- `AgentOverlay.swift` — same features as Overlay.swift but uses `AgentOverlayApp` class name
- `agents.conf` — local config (different from ~/.termavatar/config)
- `notify-avatar.sh` — local version reads from agents.conf
- This is the version actually running; termavatar repo is the clean open-source version

## Build & test
```bash
make clean && make build          # compiles to build/
bash tests/run_tests.sh           # 26 tests, uses temp HOME
```

## Common pitfalls
- `NSWindow.OrderingMode` has no `.front` — use `.orderFrontRegardless()`
- `activateIgnoringOtherApps` deprecated in macOS 14 — use `app.activate()`
- Ghostty can run as multiple processes (e.g. launched from a panel) — use `bundleIdentifier` matching + `--pid` targeting, not name-based matching
- Can't use app-level activate to target a specific window; must use AXUIElement per-window operations
- `notify-avatar.sh` must only get frontmost window (`window 1`), NOT all windows — otherwise it notifies the wrong avatar
- `set -euo pipefail` in test scripts can hide error messages from subcommands — use `|| true`
- zsh `rm -f glob*` errors when no matches — use `2>/dev/null`

## Multi-instance support
- A single terminal app (e.g. Ghostty) can run as multiple OS-level processes (PIDs), each with its own windows
- `WindowInstance(keyword, pid)` is the composite key — one overlay per keyword per terminal process
- Watcher uses `bundleIdentifier` matching (not name-based) to avoid matching helper processes like "Ghostty Networking"
- Watcher passes `--pid` to each overlay so it only searches windows in that specific process
- Overlay's `WindowTracker` accepts `targetPID` and filters `NSRunningApplication` by it

## Known limitations & future work
- No auto-start launchd plist (README suggests zshrc approach)

## User preferences
- NO breathing animation / flickering — user explicitly said "闪了不好"
- NO status text labels (waiting/thinking/etc) — user said "那四个状态,就不要了吧"
- Red dot should be small (12px) not large
- 10fps is enough, don't increase
- Keep CPU usage low
- User communicates in Chinese, prefers concise responses
