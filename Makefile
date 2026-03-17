PREFIX ?= /usr/local
CONFIG_DIR = $(HOME)/.termavatar

SWIFTC = swiftc
SWIFTFLAGS = -O -framework SwiftUI -framework AppKit -framework ApplicationServices -framework ServiceManagement

BUILD_DIR = build
APP_NAME = Termavatar.app
APP_DIR = $(BUILD_DIR)/$(APP_NAME)
APP_BIN = $(APP_DIR)/Contents/MacOS/termavatar

# All source files for the unified binary
SOURCES = Sources/main.swift Sources/Overlay.swift Sources/Watcher.swift \
          Sources/MenuBar.swift Sources/Config.swift

.PHONY: all app build install uninstall clean

all: app

# Build the .app bundle (recommended)
app:
	mkdir -p $(APP_DIR)/Contents/MacOS
	mkdir -p $(APP_DIR)/Contents/Resources
	$(SWIFTC) $(SWIFTFLAGS) -o $(APP_BIN) $(SOURCES)
	cp Info.plist $(APP_DIR)/Contents/
	@echo ""
	@echo "Built $(APP_DIR)"
	@echo "Run:  open $(APP_DIR)"

# Alias for backwards compatibility — also creates CLI wrapper scripts
build: app
	@echo '#!/bin/bash' > $(BUILD_DIR)/termavatar-overlay
	@echo 'SELF_DIR="$$(cd "$$(dirname "$$0")" && pwd)"' >> $(BUILD_DIR)/termavatar-overlay
	@echo 'BIN="$$SELF_DIR/Termavatar.app/Contents/MacOS/termavatar"' >> $(BUILD_DIR)/termavatar-overlay
	@echo 'if [ "$${1:-}" = "--help" ]; then' >> $(BUILD_DIR)/termavatar-overlay
	@echo '    echo "USAGE: termavatar-overlay <image> [--name N] [--title T] [--app A] [--size S] [--corner C] [--opacity O] [--pid P]"' >> $(BUILD_DIR)/termavatar-overlay
	@echo '    exit 0' >> $(BUILD_DIR)/termavatar-overlay
	@echo 'fi' >> $(BUILD_DIR)/termavatar-overlay
	@echo 'exec "$$BIN" --overlay "$$@"' >> $(BUILD_DIR)/termavatar-overlay
	chmod +x $(BUILD_DIR)/termavatar-overlay
	@echo '#!/bin/bash' > $(BUILD_DIR)/termavatar-watcher
	@echo 'SELF_DIR="$$(cd "$$(dirname "$$0")" && pwd)"' >> $(BUILD_DIR)/termavatar-watcher
	@echo 'BIN="$$SELF_DIR/Termavatar.app/Contents/MacOS/termavatar"' >> $(BUILD_DIR)/termavatar-watcher
	@echo '"$$BIN" --watch "$$@"' >> $(BUILD_DIR)/termavatar-watcher
	chmod +x $(BUILD_DIR)/termavatar-watcher

install: app
	mkdir -p $(PREFIX)/bin
	mkdir -p $(CONFIG_DIR)
	cp -R $(APP_DIR) /Applications/$(APP_NAME)
	@echo "Installed to /Applications/$(APP_NAME)"

uninstall:
	rm -rf /Applications/$(APP_NAME)
	rm -f $(PREFIX)/bin/termavatar

clean:
	rm -rf $(BUILD_DIR)
