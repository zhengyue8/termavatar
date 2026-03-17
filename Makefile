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

# Alias for backwards compatibility
build: app

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
