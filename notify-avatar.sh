#!/bin/bash
# notify-avatar.sh — Signal termavatar that Claude Code needs attention.
# Called by Claude Code's Notification hook.
#
# Gets the FOCUSED terminal window title (not all windows) and matches
# it against configured keywords to notify the correct avatar.

NOTIFY_DIR="$HOME/.termavatar/notify"
CONF="$HOME/.termavatar/config"
mkdir -p "$NOTIFY_DIR"
[ -f "$CONF" ] || exit 0

# Walk up the process tree to find the terminal process.
find_terminal_pid() {
    local pid=$$
    while [ "$pid" -gt 1 ]; do
        local pname
        pname=$(ps -o comm= -p "$pid" 2>/dev/null)
        if echo "$pname" | grep -qiE "ghostty|iterm|kitty|wezterm|alacritty|terminal"; then
            echo "$pid"
            return
        fi
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    done
}

TERM_PID=$(find_terminal_pid)
[ -z "$TERM_PID" ] && exit 0

# Get the terminal app name for the osascript query.
TERM_NAME=$(ps -o comm= -p "$TERM_PID" 2>/dev/null | xargs basename 2>/dev/null)

# Get ONLY the frontmost (focused) window title — not all windows.
# "window 1" in System Events is the most recently active window.
TITLE=$(osascript -e '
tell application "System Events"
    set termProcs to every process whose unix id is '"$TERM_PID"'
    if (count of termProcs) > 0 then
        return name of window 1 of item 1 of termProcs
    end if
end tell
' 2>/dev/null)

[ -z "$TITLE" ] && exit 0

# Match the focused window title against configured keywords
while IFS='|' read -r keyword rest; do
    [ -z "$keyword" ] && continue
    [[ "$keyword" == \#* ]] && continue
    if echo "$TITLE" | grep -q "$keyword"; then
        touch "$NOTIFY_DIR/$keyword"
        exit 0
    fi
done < "$CONF"
