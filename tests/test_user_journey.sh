#!/bin/bash
# test_user_journey.sh — Simulate a new user's experience from clone to usage.
# Uses a temporary HOME to avoid touching real config.
#
# Usage: bash tests/test_user_journey.sh

set -euo pipefail

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
TEST_HOME=$(mktemp -d)
ORIG_HOME="$HOME"
PASS=0
FAIL=0

cleanup() {
    # Kill any test overlay processes
    pkill -f "termavatar-overlay.*TESTUSER" 2>/dev/null || true
    rm -rf "$TEST_HOME"
    export HOME="$ORIG_HOME"
}
trap cleanup EXIT

export HOME="$TEST_HOME"

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
section() { echo ""; echo "━━━ Step $1 ━━━"; }

echo "╔══════════════════════════════════════════════╗"
echo "║  termavatar — New User Journey Test          ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Simulating: git clone → build → add avatar → watch → verify"
echo "Test HOME: $TEST_HOME"

# ─────────────────────────────────────────────
section "1: git clone & build"
# ─────────────────────────────────────────────

echo "  (Using existing repo at $PROJ instead of cloning)"

# Build
if make -C "$PROJ" clean build >/dev/null 2>&1; then
    pass "make build — compiles without errors"
else
    fail "make build — compilation failed"
fi

if [ -x "$PROJ/build/termavatar-overlay" ] && [ -x "$PROJ/build/termavatar-watcher" ]; then
    pass "Binaries exist: termavatar-overlay, termavatar-watcher"
else
    fail "Binaries missing after build"
fi

# Verify CLI script is executable
if [ -x "$PROJ/termavatar" ]; then
    pass "CLI script (termavatar) is executable"
else
    fail "CLI script not executable"
fi

# ─────────────────────────────────────────────
section "2: termavatar (no args — show help)"
# ─────────────────────────────────────────────

HELP_OUT=$("$PROJ/termavatar" 2>&1 || true)
if echo "$HELP_OUT" | grep -q "add.*photo" && echo "$HELP_OUT" | grep -q "watch"; then
    pass "Help text shows available commands"
else
    fail "Help text incomplete or missing"
fi

# ─────────────────────────────────────────────
section "3: termavatar add (create first avatar)"
# ─────────────────────────────────────────────

# Check Pillow is available
if ! python3 -c "import PIL" 2>/dev/null; then
    echo "  SKIP: Pillow not installed — cannot test 'add' command"
    echo "  (User would need: pip3 install Pillow)"
else
    # Create a test photo
    TEST_PHOTO="$TEST_HOME/alice_photo.jpg"
    python3 -c "
from PIL import Image
img = Image.new('RGB', (400, 400), (100, 150, 200))
img.save('$TEST_PHOTO')
"

    ADD_OUT=$("$PROJ/termavatar" add Alice "$TEST_PHOTO" 2>&1)
    if echo "$ADD_OUT" | grep -q "Added avatar"; then
        pass "termavatar add Alice — reports success"
    else
        fail "termavatar add Alice — unexpected output: $ADD_OUT"
    fi

    # Verify directory structure was created
    if [ -d "$TEST_HOME/.termavatar" ] && [ -d "$TEST_HOME/.termavatar/avatars" ]; then
        pass "~/.termavatar/ directory structure created"
    else
        fail "~/.termavatar/ directory not created"
    fi

    # Verify config file
    if [ -f "$TEST_HOME/.termavatar/config" ] && grep -q "^Alice|" "$TEST_HOME/.termavatar/config"; then
        pass "Config file has Alice entry"
    else
        fail "Config file missing or no Alice entry"
    fi

    # Verify circular avatar PNG
    if [ -f "$TEST_HOME/.termavatar/avatars/Alice.png" ]; then
        # Check it's actually a PNG with alpha (circular crop)
        FILE_TYPE=$(file "$TEST_HOME/.termavatar/avatars/Alice.png" 2>/dev/null)
        if echo "$FILE_TYPE" | grep -qi "PNG"; then
            pass "Circular avatar Alice.png generated (PNG format)"
        else
            fail "Avatar file exists but not PNG: $FILE_TYPE"
        fi
    else
        fail "Circular avatar PNG not generated"
    fi

    # ─────────────────────────────────────────
    section "4: termavatar add (second avatar, custom corner & size)"
    # ─────────────────────────────────────────

    TEST_PHOTO2="$TEST_HOME/bob_photo.png"
    python3 -c "
from PIL import Image
img = Image.new('RGB', (300, 500), (200, 100, 50))
img.save('$TEST_PHOTO2')
"

    ADD_OUT2=$("$PROJ/termavatar" add Bob "$TEST_PHOTO2" tr 120 2>&1)
    if echo "$ADD_OUT2" | grep -q "Added avatar"; then
        pass "termavatar add Bob tr 120 — custom corner and size"
    else
        fail "termavatar add Bob — unexpected output"
    fi

    # Verify corner and size in config
    BOB_LINE=$(grep "^Bob|" "$TEST_HOME/.termavatar/config")
    if echo "$BOB_LINE" | grep -q "|tr|120"; then
        pass "Bob config: corner=tr, size=120"
    else
        fail "Bob config wrong: $BOB_LINE"
    fi

    # ─────────────────────────────────────────
    section "5: termavatar list"
    # ─────────────────────────────────────────

    LIST_OUT=$("$PROJ/termavatar" list 2>&1)
    if echo "$LIST_OUT" | grep -q "Alice" && echo "$LIST_OUT" | grep -q "Bob"; then
        pass "termavatar list — shows both Alice and Bob"
    else
        fail "termavatar list — missing entries"
    fi

    if echo "$LIST_OUT" | grep -q "Watcher"; then
        pass "termavatar list — shows watcher status section"
    else
        fail "termavatar list — missing watcher status"
    fi

    # ─────────────────────────────────────────
    section "6: termavatar conf"
    # ─────────────────────────────────────────

    CONF_OUT=$("$PROJ/termavatar" conf 2>&1)
    if echo "$CONF_OUT" | grep -q "Alice|Alice" && echo "$CONF_OUT" | grep -q "Bob|Bob"; then
        pass "termavatar conf — prints config correctly"
    else
        fail "termavatar conf — output wrong"
    fi

    # ─────────────────────────────────────────
    section "7: termavatar watch (start watcher)"
    # ─────────────────────────────────────────

    WATCH_OUT=$("$PROJ/termavatar" watch 2>&1)
    if echo "$WATCH_OUT" | grep -q "Watcher started"; then
        pass "termavatar watch — watcher started"
    else
        fail "termavatar watch — unexpected output: $WATCH_OUT"
    fi

    sleep 2

    # Check watcher is actually running
    if pgrep -f "termavatar-watcher" >/dev/null 2>&1; then
        pass "Watcher process is running"
    else
        fail "Watcher process not found"
    fi

    # Check log file was created
    if [ -f "$TEST_HOME/.termavatar/watcher.log" ]; then
        pass "Watcher log file created at ~/.termavatar/watcher.log"
    else
        fail "Watcher log file not created"
    fi

    # ─────────────────────────────────────────
    section "8: termavatar watch (duplicate — should warn)"
    # ─────────────────────────────────────────

    WATCH2_OUT=$("$PROJ/termavatar" watch 2>&1)
    if echo "$WATCH2_OUT" | grep -q "already running"; then
        pass "Second 'watch' warns already running"
    else
        fail "Second 'watch' did not warn: $WATCH2_OUT"
    fi

    # ─────────────────────────────────────────
    section "9: termavatar log"
    # ─────────────────────────────────────────

    LOG_OUT=$("$PROJ/termavatar" log 2>&1)
    if [ -n "$LOG_OUT" ]; then
        pass "termavatar log — shows output"
    else
        fail "termavatar log — empty"
    fi

    # ─────────────────────────────────────────
    section "10: Overlay direct launch test"
    # ─────────────────────────────────────────

    # Launch overlay with a non-matching title so it stays alive but hidden
    "$PROJ/build/termavatar-overlay" "$TEST_HOME/.termavatar/avatars/Alice.png" \
        --name TESTUSER --title NONEXISTENT_WINDOW_XYZ --app ghostty &
    OVERLAY_PID=$!
    sleep 1

    if kill -0 "$OVERLAY_PID" 2>/dev/null; then
        pass "Overlay process launches and stays alive"
    else
        fail "Overlay process crashed on startup"
    fi
    kill "$OVERLAY_PID" 2>/dev/null; wait "$OVERLAY_PID" 2>/dev/null || true

    # ─────────────────────────────────────────
    section "11: termavatar remove"
    # ─────────────────────────────────────────

    REMOVE_OUT=$("$PROJ/termavatar" remove Alice 2>&1)
    if echo "$REMOVE_OUT" | grep -q "Removed"; then
        pass "termavatar remove Alice — success"
    else
        fail "termavatar remove Alice — unexpected: $REMOVE_OUT"
    fi

    # Verify Alice is gone from config
    if ! grep -q "^Alice|" "$TEST_HOME/.termavatar/config"; then
        pass "Alice removed from config file"
    else
        fail "Alice still in config after remove"
    fi

    # Bob should still be there
    if grep -q "^Bob|" "$TEST_HOME/.termavatar/config"; then
        pass "Bob still in config after removing Alice"
    else
        fail "Bob disappeared after removing Alice"
    fi

    # ─────────────────────────────────────────
    section "12: termavatar unwatch (stop everything)"
    # ─────────────────────────────────────────

    UNWATCH_OUT=$("$PROJ/termavatar" unwatch 2>&1)
    if echo "$UNWATCH_OUT" | grep -qi "stopped\|nothing"; then
        pass "termavatar unwatch — clean shutdown"
    else
        fail "termavatar unwatch — unexpected: $UNWATCH_OUT"
    fi

    sleep 1

    if ! pgrep -f "termavatar-watcher" >/dev/null 2>&1; then
        pass "Watcher process stopped"
    else
        fail "Watcher still running after unwatch"
    fi

    # ─────────────────────────────────────────
    section "13: notify-avatar.sh (hook script)"
    # ─────────────────────────────────────────

    if [ -x "$PROJ/notify-avatar.sh" ]; then
        pass "notify-avatar.sh exists and is executable"
    else
        fail "notify-avatar.sh missing or not executable"
    fi

    # Should exit cleanly when not inside a terminal
    (bash "$PROJ/notify-avatar.sh" 2>/dev/null) || true
    if [ ! -f "$TEST_HOME/.termavatar/notify/Bob" ]; then
        pass "notify-avatar.sh does not create false signals"
    else
        fail "notify-avatar.sh created signal outside terminal"
    fi
fi

# ─────────────────────────────────────────────
section "14: Edge cases"
# ─────────────────────────────────────────────

# add with missing photo
ERR_OUT=$("$PROJ/termavatar" add BadUser /nonexistent/photo.jpg 2>&1 || true)
if echo "$ERR_OUT" | grep -qi "error\|not found"; then
    pass "add with missing photo — shows error"
else
    fail "add with missing photo — no error shown"
fi

# remove non-existent
ERR_OUT2=$("$PROJ/termavatar" remove NoSuchUser 2>&1 || true)
if echo "$ERR_OUT2" | grep -qi "not found"; then
    pass "remove non-existent — shows error"
else
    fail "remove non-existent — no error shown"
fi

# ─────────────────────────────────────────────
echo ""
echo "━━━ Results ━━━"
# ─────────────────────────────────────────────

TOTAL=$((PASS + FAIL))
echo ""
echo "  $PASS passed, $FAIL failed (out of $TOTAL tests)"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo "Some tests failed!"
    exit 1
else
    echo "All tests passed! ✓"
    echo ""
    echo "The full user journey works:"
    echo "  clone → build → add avatar → list → watch → log → remove → unwatch"
    exit 0
fi
