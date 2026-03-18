#!/bin/bash
# termavatar health check — runs via cron daily
# Kills duplicate watchers, ensures single instance

LOGFILE="$HOME/.termavatar/health.log"
NOW=$(date "+%Y-%m-%d %H:%M")

# Count avatar-watcher processes
WATCHER_COUNT=$(pgrep -f "agent-avatar/avatar-watcher" | wc -l | tr -d ' ')

if [ "$WATCHER_COUNT" -gt 2 ]; then
    # Keep newest, kill the rest
    PIDS=$(pgrep -f "agent-avatar/avatar-watcher" | sort -n)
    KEEP=$(echo "$PIDS" | tail -2)
    for p in $PIDS; do
        if ! echo "$KEEP" | grep -q "^${p}$"; then
            kill "$p" 2>/dev/null
            echo "[$NOW] Killed duplicate watcher PID $p" >> "$LOGFILE"
        fi
    done
fi

# Kill duplicate overlays (same keyword+pid spawned twice)
pgrep -f "agent-overlay" | while read pid; do
    ARGS=$(ps -p "$pid" -o args= 2>/dev/null)
    echo "$pid $ARGS"
done | sort -k3 | awk '{key=$3" "$NF; if(seen[key]) print $1; seen[key]=1}' | while read dup; do
    kill "$dup" 2>/dev/null
    echo "[$NOW] Killed duplicate overlay PID $dup" >> "$LOGFILE"
done

# Ensure app is in /Applications
if [ ! -d "/Applications/Termavatar.app" ]; then
    if [ -d "$HOME/Projects/termavatar/build/Termavatar.app" ]; then
        cp -R "$HOME/Projects/termavatar/build/Termavatar.app" /Applications/
        echo "[$NOW] Restored Termavatar.app to /Applications" >> "$LOGFILE"
    fi
fi
