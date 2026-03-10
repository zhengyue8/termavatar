# termavatar

Floating circular avatar photos for your terminal windows.

![Demo](assets/demo.gif)

## What is this?

termavatar is a macOS tool that attaches floating circular avatar images to terminal windows. It matches keywords in window titles to decide which avatar to show on which terminal.

It is designed for people who run multiple AI coding agents (such as Claude Code) in separate terminal windows and want to give each agent a visual identity at a glance.

**A concrete example:** You have three terminals open, each running a different Claude Code agent. You have named them Alice, Bob, and Charlie by setting their window titles. Without termavatar, all three terminals look identical and you constantly mix them up. With termavatar, Alice's terminal has her photo in the corner, Bob has his, and Charlie has his. You can instantly tell which agent is which, even when windows overlap.

The avatars behave like a natural part of the terminal window. They float above their terminal but hide behind other apps when you switch focus, so they never get in the way.

## Features

- **Title-based matching** -- assign avatars based on substring matching against terminal window titles
- **Proper z-order layering** -- avatars float above their terminal but hide behind other apps, behaving like a native window element
- **Multi-terminal support** -- works with Ghostty, iTerm2, Kitty, WezTerm, Alacritty, and Terminal.app
- **Corner placement** -- place the avatar in any corner of the terminal window (top-left, top-right, bottom-left, bottom-right)
- **Automatic circular cropping** -- any photo you provide is automatically cropped and masked into a circle
- **Name labels** -- an optional text label is displayed below each avatar
- **Background watcher** -- a daemon monitors window titles and spawns or removes overlays automatically
- **Hot-reload** -- edit the config file and changes take effect within seconds, no restart required
- **Simple CLI** -- one command to add, remove, list, or manage avatars

## Requirements

Before you begin, make sure you have the following:

- **macOS 13 (Ventura) or later.** termavatar uses modern macOS APIs for window management. It will not work on older versions of macOS.

- **Xcode Command Line Tools.** These provide the Swift compiler used to build the project. If you do not have them, install them by running:

  ```
  xcode-select --install
  ```

- **Python 3 with Pillow.** The `add` command uses a Python script to crop your photo into a circle. Pillow is the image processing library it depends on. Install it with:

  ```
  pip3 install Pillow
  ```

- **Accessibility permission.** termavatar reads window titles through the macOS Accessibility API. You must grant permission to both the termavatar binaries and your terminal application. See the Installation section below for details.

## Installation

### Step 1: Clone the repository

```
git clone https://github.com/youruser/termavatar.git
cd termavatar
```

### Step 2: Build the project

```
make build
```

This compiles two Swift binaries into the `build/` directory: `termavatar-overlay` (the floating window) and `termavatar-watcher` (the background daemon).

### Step 3: Install

```
make install
```

This copies the binaries and the CLI script to `/usr/local/bin/`. If you prefer a different location, you can specify it:

```
make install PREFIX=$HOME/.local
```

Alternatively, you can skip `make install` and run termavatar directly from the cloned directory. The CLI script will find the binaries in the same folder.

### Step 4: Grant Accessibility permission

termavatar needs Accessibility access to read window titles and position overlays. You must grant permission in two places:

1. Open **System Settings** (the gear icon in your Dock or Apple menu).
2. Navigate to **Privacy & Security > Accessibility**.
3. Click the **+** button and add your **terminal application** (for example, Ghostty, iTerm2, or whichever terminal you use).
4. The first time you run `termavatar watch`, macOS will prompt you to also grant access to the termavatar watcher process. Click **Allow**.

If you do not see a prompt, you may need to manually add the `termavatar-watcher` and `termavatar-overlay` binaries. They are located at `/usr/local/bin/termavatar-watcher` and `/usr/local/bin/termavatar-overlay` (or wherever you installed them).

After granting permissions, you may need to restart your terminal for the changes to take effect.

## Quick Start

Follow these steps to set up your first avatar.

### 1. Add an avatar

Pick a name and a photo. The name will be used as the keyword to match against window titles.

```
termavatar add Alice ~/Downloads/alice.jpg
```

This crops the photo into a circle and saves it to `~/.termavatar/avatars/Alice.png`. It also adds an entry to the config file at `~/.termavatar/config`.

### 2. Set your terminal window title

Your terminal window title must contain the keyword (in this case, "Alice") for termavatar to match it. How you set the title depends on your terminal. The simplest method that works in most terminals is:

```
printf '\033]0;Alice\007'
```

See the "How to set terminal window titles" section below for terminal-specific instructions.

### 3. Start the watcher

```
termavatar watch
```

The watcher runs in the background. It checks terminal window titles every 2 seconds. When it finds a window whose title contains "Alice", it spawns an overlay process that displays the avatar in the bottom-right corner of that window.

### 4. See the avatar

The circular avatar photo should now appear in the corner of your terminal window. It will follow the window if you move or resize it, and it will hide behind other applications when you switch focus.

To stop the watcher and remove all overlays:

```
termavatar unwatch
```

## Usage

### termavatar add

```
termavatar add <name> <photo> [corner] [size]
```

Add an avatar assignment. The photo is automatically cropped into a circle.

- `name` -- the keyword to match in window titles (also used as the display label)
- `photo` -- path to any image file (JPG, PNG, etc.)
- `corner` -- where to place the avatar: `tl` (top-left), `tr` (top-right), `bl` (bottom-left), `br` (bottom-right). Default: `br`
- `size` -- avatar diameter in pixels. Default: `90`

Examples:

```
termavatar add Alice ~/Photos/alice.jpg
termavatar add Bob ~/Photos/bob.png tr 120
termavatar add Charlie ~/Photos/charlie.jpg bl 80
```

### termavatar remove

```
termavatar remove <name>
```

Remove an avatar assignment from the config file.

```
termavatar remove Alice
```

### termavatar list

```
termavatar list
```

Show all configured avatars, running overlay processes, and watcher status.

### termavatar watch

```
termavatar watch
```

Start the background watcher daemon. It monitors terminal window titles and automatically spawns or removes overlay processes as windows appear and disappear. Log output goes to `~/.termavatar/watcher.log`.

### termavatar unwatch

```
termavatar unwatch
```

Stop the watcher and all running overlay processes.

### termavatar restart

```
termavatar restart
```

Stop and restart the watcher. Useful after making manual changes to the config file.

### termavatar conf

```
termavatar conf
```

Print the contents of the config file to the terminal.

### termavatar edit

```
termavatar edit
```

Open the config file in your default editor (`$EDITOR`, or `vi` if not set).

### termavatar log

```
termavatar log
```

Show the last 20 lines of the watcher log file (`~/.termavatar/watcher.log`). Useful for debugging.

## Configuration

The config file is located at `~/.termavatar/config`. Each line defines one avatar assignment using pipe-delimited fields:

```
keyword|display_name|image_path|corner|size
```

| Field          | Description                                                        |
|----------------|--------------------------------------------------------------------|
| `keyword`      | Substring to match in the terminal window title                    |
| `display_name` | Label shown below the avatar circle                                |
| `image_path`   | Absolute path to the circular PNG (generated by `termavatar add`)  |
| `corner`       | Placement corner: `tl`, `tr`, `bl`, or `br`                       |
| `size`         | Avatar diameter in pixels                                          |

Example config file:

```
Alice|Alice|/Users/you/.termavatar/avatars/Alice.png|br|90
Bob|Bob|/Users/you/.termavatar/avatars/Bob.png|tr|120
Charlie|Charlie|/Users/you/.termavatar/avatars/Charlie.png|bl|80
```

**How keyword matching works:** The watcher scans all visible terminal windows every 2 seconds. For each window, it checks whether the window title contains any of the configured keywords as a substring. The match is case-sensitive. If a window title is "Claude Code - Alice - ~/project", and you have a keyword "Alice", it will match.

Lines starting with `#` are treated as comments and ignored. The config is hot-reloaded every 10 seconds, so you can edit it while the watcher is running and changes will take effect shortly.

## How to set terminal window titles

For termavatar to work, your terminal window title must contain the keyword you configured. Here is how to set window titles in each supported terminal.

### Ghostty

Add to your Ghostty config file (`~/.config/ghostty/config`):

```
title = Alice
```

Or set it dynamically from the shell:

```
printf '\033]0;Alice\007'
```

### iTerm2

Go to **Profiles > General > Title** and set a custom title. Alternatively, use the escape sequence from the shell:

```
printf '\033]0;Alice\007'
```

Note: In iTerm2, you may need to disable "Applications in terminal may change the title" under **Profiles > General** if the title keeps getting overwritten.

### Kitty

Add to your Kitty config (`~/.config/kitty/kitty.conf`):

```
tab_title_template {title}
```

Then set the title from the shell:

```
printf '\033]0;Alice\007'
```

### WezTerm

Set the title from the shell:

```
printf '\033]0;Alice\007'
```

Or configure it in your `wezterm.lua` file.

### Alacritty

Add to your Alacritty config (`~/.config/alacritty/alacritty.toml`):

```toml
[window]
title = "Alice"
```

Or use the escape sequence from the shell.

### Terminal.app

Use the escape sequence from the shell:

```
printf '\033]0;Alice\007'
```

Note: Terminal.app may override titles with the shell command name. Go to **Preferences > Profiles > Window > Title** and uncheck everything except "Window title set by shell".

## Auto-start on login

To automatically start the watcher when you open a terminal, add this to your `~/.zshrc` (or `~/.bashrc`):

```bash
# Start termavatar watcher if not already running
if ! pgrep -f termavatar-watcher > /dev/null 2>&1; then
    termavatar watch
fi
```

This checks whether the watcher is already running before starting it, so opening additional terminal windows will not spawn duplicate watchers.

## How it works

termavatar has three components:

1. **CLI script** (`termavatar`) -- a Bash script that manages avatars and controls the watcher. It handles the `add`, `remove`, `list`, `watch`, `unwatch`, and other commands.

2. **Watcher** (`termavatar-watcher`) -- a Swift daemon that polls the macOS Accessibility API every 2 seconds to discover terminal windows. When a window title matches a configured keyword, the watcher spawns an overlay process. When the window disappears, the watcher terminates the corresponding overlay.

3. **Overlay** (`termavatar-overlay`) -- a Swift application that creates a borderless, transparent NSWindow displaying a circular avatar image. It uses `CGWindowListCopyWindowInfo` to find the target terminal's Core Graphics window ID, then calls `window.order(.above, relativeTo:)` to layer the avatar directly above that specific window. This is what makes avatars hide behind other apps when you switch focus, instead of floating on top of everything. The overlay updates its position at 30 fps to track window moves and resizes.

When you run `termavatar add`, the CLI also invokes a Python script (`crop_avatar.py`) that uses Pillow to center-crop the input image to a square, resize it, and apply a circular alpha mask.

## Supported terminals

- Ghostty
- iTerm2
- Kitty
- WezTerm
- Alacritty
- Terminal.app

## Troubleshooting

**Avatar is not showing up**

- Make sure you have granted Accessibility permission to both your terminal application and the termavatar binaries. Go to **System Settings > Privacy & Security > Accessibility** and verify they are listed and enabled.
- After granting permissions, restart your terminal and run `termavatar restart`.
- Check the log with `termavatar log` to see if the watcher is detecting your windows.

**Avatar shows on the wrong terminal**

- Check that the keyword in your config matches the correct window title. Run `termavatar conf` to see your config, and compare the keywords against the actual window titles.
- Remember that keyword matching is case-sensitive. "alice" will not match a window titled "Alice".

**Avatar floats on top of other apps instead of hiding**

- Make sure you have the latest version of termavatar. Older versions may have used a floating window level instead of the correct z-order approach.
- Run `termavatar restart` to respawn all overlays.

**Watcher is not starting**

- Run `termavatar log` to check for error messages.
- Make sure the `termavatar-watcher` binary exists and is executable. Run `which termavatar-watcher` to verify.
- If you installed to a custom prefix, make sure it is in your `$PATH`.

**Avatar disappears when I switch desktops/spaces**

- This is expected behavior. The avatar is layered relative to the terminal window, so it follows the same Space as the terminal.

**"Error: file not found" when adding an avatar**

- Make sure the image path is correct. Use an absolute path or a path relative to your current directory.

## Contributing

Contributions are welcome. Please open an issue to discuss your idea before submitting a pull request.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-idea`)
3. Commit your changes
4. Open a pull request

## License

MIT License. See [LICENSE](LICENSE) for details.
