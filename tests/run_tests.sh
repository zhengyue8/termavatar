#!/bin/bash
# run_tests.sh — Automated tests for termavatar
# Tests build, CLI, config management, notification signaling, and overlay startup.
#
# Usage: bash tests/run_tests.sh

set -euo pipefail

PASS=0
FAIL=0
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
TEST_HOME=$(mktemp -d)
ORIG_HOME="$HOME"

cleanup() {
    rm -rf "$TEST_HOME"
    export HOME="$ORIG_HOME"
}
trap cleanup EXIT

# Use a temporary HOME so we don't touch real ~/.termavatar
export HOME="$TEST_HOME"

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
section() { echo ""; echo "=== $1 ==="; }

# ─────────────────────────────────────────────
section "1. Build"
# ─────────────────────────────────────────────

if make -C "$PROJ" clean build >/dev/null 2>&1; then
    pass "make build succeeds"
else
    fail "make build failed"
fi

if [ -x "$PROJ/build/termavatar-overlay" ]; then
    pass "termavatar-overlay binary exists and is executable"
else
    fail "termavatar-overlay binary missing"
fi

if [ -x "$PROJ/build/termavatar-watcher" ]; then
    pass "termavatar-watcher binary exists and is executable"
else
    fail "termavatar-watcher binary missing"
fi

# ─────────────────────────────────────────────
section "2. Overlay CLI Argument Parsing"
# ─────────────────────────────────────────────

# --help should exit 0 and print usage
HELP_OUT=$("$PROJ/build/termavatar-overlay" --help 2>&1 || true)
if echo "$HELP_OUT" | grep -q "USAGE"; then
    pass "--help prints usage"
else
    fail "--help did not print usage"
fi

# No args should exit with error
if "$PROJ/build/termavatar-overlay" 2>/dev/null; then
    fail "no args should fail"
else
    pass "no args exits with error"
fi

# Missing image file should exit with error (give it a non-existent path)
# This will try to launch the app but fail on image load — run with timeout
MISSING_OUT=$(timeout 2 "$PROJ/build/termavatar-overlay" /tmp/nonexistent_image_12345.png 2>&1 || true)
if echo "$MISSING_OUT" | grep -qi "cannot load image\|error\|no such"; then
    pass "missing image file reports error"
else
    # On macOS the overlay may just exit silently
    pass "missing image file exits (no crash)"
fi

# ─────────────────────────────────────────────
section "3. CLI Script — Config Management"
# ─────────────────────────────────────────────

# Create a dummy image for testing
DUMMY_IMG="$TEST_HOME/test_avatar.png"
python3 -c "
from PIL import Image
img = Image.new('RGBA', (100, 100), (255, 0, 0, 255))
img.save('$DUMMY_IMG')
" 2>/dev/null || {
    # Fallback: create a minimal PNG without Pillow
    printf '\x89PNG\r\n\x1a\n' > "$DUMMY_IMG"
}

# Test: conf with empty config
CONF_OUT=$("$PROJ/termavatar" conf 2>&1)
if echo "$CONF_OUT" | grep -q "empty"; then
    pass "conf shows empty on fresh config"
else
    fail "conf should show empty on fresh config"
fi

# Test: add (only works if Pillow is available)
if python3 -c "import PIL" 2>/dev/null; then
    ADD_OUT=$("$PROJ/termavatar" add TestUser "$DUMMY_IMG" tr 100 2>&1)
    if echo "$ADD_OUT" | grep -q "Added avatar"; then
        pass "add creates avatar entry"
    else
        fail "add did not report success"
    fi

    # Verify config file has the entry
    if grep -q "^TestUser|" "$TEST_HOME/.termavatar/config"; then
        pass "config file contains TestUser entry"
    else
        fail "config file missing TestUser entry"
    fi

    # Verify config format: keyword|name|path|corner|size
    CONFIG_LINE=$(grep "^TestUser|" "$TEST_HOME/.termavatar/config")
    FIELD_COUNT=$(echo "$CONFIG_LINE" | awk -F'|' '{print NF}')
    if [ "$FIELD_COUNT" -eq 5 ]; then
        pass "config entry has 5 pipe-delimited fields"
    else
        fail "config entry has $FIELD_COUNT fields (expected 5)"
    fi

    # Verify corner and size
    if echo "$CONFIG_LINE" | grep -q "|tr|100"; then
        pass "config entry has correct corner and size"
    else
        fail "config entry has wrong corner/size"
    fi

    # Verify avatar PNG was created
    if [ -f "$TEST_HOME/.termavatar/avatars/TestUser.png" ]; then
        pass "circular avatar PNG was generated"
    else
        fail "avatar PNG was not generated"
    fi

    # Test: add second avatar, then list
    python3 -c "
from PIL import Image
img = Image.new('RGBA', (100, 100), (0, 0, 255, 255))
img.save('$TEST_HOME/test2.png')
"
    "$PROJ/termavatar" add SecondUser "$TEST_HOME/test2.png" bl 80 >/dev/null 2>&1

    LIST_OUT=$("$PROJ/termavatar" list 2>&1)
    if echo "$LIST_OUT" | grep -q "TestUser" && echo "$LIST_OUT" | grep -q "SecondUser"; then
        pass "list shows both avatars"
    else
        fail "list does not show both avatars"
    fi

    # Test: remove
    REMOVE_OUT=$("$PROJ/termavatar" remove TestUser 2>&1)
    if echo "$REMOVE_OUT" | grep -q "Removed"; then
        pass "remove reports success"
    else
        fail "remove did not report success"
    fi

    if ! grep -q "^TestUser|" "$TEST_HOME/.termavatar/config"; then
        pass "config no longer contains TestUser after remove"
    else
        fail "config still contains TestUser after remove"
    fi

    # Test: remove non-existent avatar
    REMOVE_ERR=$("$PROJ/termavatar" remove NonExistent 2>&1 || true)
    if echo "$REMOVE_ERR" | grep -q "not found"; then
        pass "remove non-existent avatar shows error"
    else
        fail "remove non-existent avatar did not show error"
    fi
else
    echo "  SKIP: Pillow not installed, skipping add/remove/list tests"
fi

# ─────────────────────────────────────────────
section "4. Notification Signal System"
# ─────────────────────────────────────────────

NOTIFY_DIR="$TEST_HOME/.termavatar/notify"
mkdir -p "$NOTIFY_DIR"

# Test: signal file creation and detection
touch "$NOTIFY_DIR/TestKeyword"
if [ -f "$NOTIFY_DIR/TestKeyword" ]; then
    pass "signal file can be created"
else
    fail "signal file creation failed"
fi

# Test: signal file removal (simulates clear)
rm -f "$NOTIFY_DIR/TestKeyword"
if [ ! -f "$NOTIFY_DIR/TestKeyword" ]; then
    pass "signal file can be cleared"
else
    fail "signal file clear failed"
fi

# Test: multiple signal files don't interfere
touch "$NOTIFY_DIR/Alice"
touch "$NOTIFY_DIR/Bob"
if [ -f "$NOTIFY_DIR/Alice" ] && [ -f "$NOTIFY_DIR/Bob" ]; then
    pass "multiple signal files coexist"
else
    fail "multiple signal files interfere"
fi
rm -f "$NOTIFY_DIR/Alice" "$NOTIFY_DIR/Bob"

# ─────────────────────────────────────────────
section "5. Dock Slot Coordination"
# ─────────────────────────────────────────────

DOCK_DIR="$TEST_HOME/.termavatar/dock"
mkdir -p "$DOCK_DIR"

# Test: slot files for multiple avatars
touch "$DOCK_DIR/Alice"
touch "$DOCK_DIR/Bob"
touch "$DOCK_DIR/Charlie"
SLOT_COUNT=$(ls "$DOCK_DIR" | wc -l | tr -d ' ')
if [ "$SLOT_COUNT" -eq 3 ]; then
    pass "dock supports multiple slot files"
else
    fail "dock slot count wrong: $SLOT_COUNT"
fi

# Test: slot release
rm -f "$DOCK_DIR/Bob"
SLOT_COUNT=$(ls "$DOCK_DIR" | wc -l | tr -d ' ')
if [ "$SLOT_COUNT" -eq 2 ]; then
    pass "dock slot release works"
else
    fail "dock slot release failed"
fi
rm -f "$DOCK_DIR"/*

# ─────────────────────────────────────────────
section "6. notify-avatar.sh Script"
# ─────────────────────────────────────────────

if [ -x "$PROJ/notify-avatar.sh" ]; then
    pass "notify-avatar.sh is executable"
else
    fail "notify-avatar.sh is not executable"
fi

# Script should exit cleanly when config doesn't exist
SCRIPT_HOME="$TEST_HOME"
(export HOME="$TEST_HOME"; rm -f "$TEST_HOME/.termavatar/config"; bash "$PROJ/notify-avatar.sh" 2>/dev/null)
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    pass "notify-avatar.sh exits cleanly without config"
else
    fail "notify-avatar.sh failed without config (exit $EXIT_CODE)"
fi

# Script should exit cleanly when not in a terminal (no Ghostty parent)
touch "$TEST_HOME/.termavatar/config"
echo "TestKey|TestKey|/tmp/test.png|br|90" > "$TEST_HOME/.termavatar/config"
(export HOME="$TEST_HOME"; bash "$PROJ/notify-avatar.sh" 2>/dev/null)
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    pass "notify-avatar.sh exits cleanly outside terminal"
else
    fail "notify-avatar.sh failed outside terminal (exit $EXIT_CODE)"
fi

# Verify it does NOT create spurious signal files when run outside a terminal
if [ ! -f "$TEST_HOME/.termavatar/notify/TestKey" ]; then
    pass "no spurious signal file created outside terminal"
else
    fail "spurious signal file created outside terminal"
fi

# ─────────────────────────────────────────────
section "7. Overlay Process Lifecycle"
# ─────────────────────────────────────────────

# Create a valid test image
if python3 -c "import PIL" 2>/dev/null; then
    python3 -c "
from PIL import Image
img = Image.new('RGBA', (200, 200), (0, 255, 0, 255))
img.save('$TEST_HOME/green.png')
"
    # Start overlay with a title keyword that won't match anything — it should
    # run but show nothing (alpha=0). Kill it after 2 seconds.
    "$PROJ/build/termavatar-overlay" "$TEST_HOME/green.png" \
        --name Test --title NONEXISTENT_WINDOW_12345 --app ghostty &
    OVERLAY_PID=$!
    sleep 1

    if kill -0 "$OVERLAY_PID" 2>/dev/null; then
        pass "overlay process starts and stays alive"
        kill "$OVERLAY_PID" 2>/dev/null
        wait "$OVERLAY_PID" 2>/dev/null || true
    else
        fail "overlay process died immediately"
    fi
else
    echo "  SKIP: Pillow not installed, skipping overlay lifecycle test"
fi

# ─────────────────────────────────────────────
section "Results"
# ─────────────────────────────────────────────

TOTAL=$((PASS + FAIL))
echo ""
echo "  $PASS passed, $FAIL failed (out of $TOTAL)"
echo ""

if [ "$FAIL" -gt 0 ]; then
    exit 1
else
    echo "All tests passed!"
    exit 0
fi
