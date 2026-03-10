# termavatar

**Floating avatars for your terminal windows.**

Attach circular avatar photos to specific terminal windows by matching window titles. Designed for multi-agent AI coding workflows where you run several coding agents side by side and want to instantly tell them apart.

![Demo](assets/demo.gif)

## Features

- **Auto-detect by window title** -- assign avatars to terminals based on title substring matching
- **Proper z-order** -- avatars float above their terminal but hide behind other apps, just like a native window element
- **Multi-terminal support** -- works with Ghostty, iTerm2, Kitty, WezTerm, Alacritty, and Terminal.app
- **Auto-start** -- optional launchd integration so avatars appear on login
- **Simple CLI** -- one command to add, remove, or list avatar assignments

## Quick Start

### Homebrew (coming soon)

```
brew install termavatar
```

### Manual Install

```
git clone https://github.com/youruser/termavatar.git
cd termavatar
make build
make install
```

## Usage

### Add an avatar

Assign an avatar image to any terminal whose title contains a given string:

```
termavatar add "claude-1" ~/avatars/blue.png
termavatar add "claude-2" ~/avatars/red.png
```

### List assignments

```
termavatar list
```

### Remove an avatar

```
termavatar remove "claude-1"
```

### Background watcher

Start the watcher process that monitors window titles and attaches overlays automatically:

```
termavatar watch
```

Stop the watcher:

```
termavatar unwatch
```

Restart after config changes:

```
termavatar restart
```

## How It Works

1. The **watcher** process polls the macOS Accessibility API to find terminal windows whose titles match your configured patterns.
2. When a match is found, it spawns an **overlay** process -- a borderless, transparent NSWindow displaying a circular avatar image.
3. The overlay uses `CGWindowListCopyWindowInfo` to locate the target terminal's window ID and calls `order(.above, relativeTo:)` to keep the avatar layered directly above that specific window. This means the avatar hides behind other apps when you switch focus, behaving like a natural part of the terminal chrome.
4. The watcher continuously tracks window moves and resizes so the avatar stays pinned to the correct corner.

## Requirements

- macOS 13 (Ventura) or later
- Accessibility permission (System Settings > Privacy & Security > Accessibility)

## Contributing

Contributions are welcome. Please open an issue to discuss your idea before submitting a pull request.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-idea`)
3. Commit your changes
4. Open a pull request

## License

MIT License. See [LICENSE](LICENSE) for details.
