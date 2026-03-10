PREFIX ?= /usr/local
CONFIG_DIR = $(HOME)/.termavatar

SWIFTC = swiftc
SWIFTFLAGS = -O -framework AppKit -framework ApplicationServices

BUILD_DIR = build

OVERLAY_SRC = Sources/Overlay.swift
WATCHER_SRC = Sources/Watcher.swift
OVERLAY_BIN = $(BUILD_DIR)/termavatar-overlay
WATCHER_BIN = $(BUILD_DIR)/termavatar-watcher

.PHONY: all build install uninstall clean

all: build

build:
	mkdir -p $(BUILD_DIR)
	$(SWIFTC) $(SWIFTFLAGS) -o $(OVERLAY_BIN) $(OVERLAY_SRC)
	$(SWIFTC) $(SWIFTFLAGS) -o $(WATCHER_BIN) $(WATCHER_SRC)

install: build
	mkdir -p $(PREFIX)/bin
	mkdir -p $(CONFIG_DIR)
	cp $(OVERLAY_BIN) $(PREFIX)/bin/termavatar-overlay
	cp $(WATCHER_BIN) $(PREFIX)/bin/termavatar-watcher
	cp termavatar $(PREFIX)/bin/termavatar
	chmod +x $(PREFIX)/bin/termavatar

uninstall:
	rm -f $(PREFIX)/bin/termavatar-overlay
	rm -f $(PREFIX)/bin/termavatar-watcher
	rm -f $(PREFIX)/bin/termavatar

clean:
	rm -rf $(BUILD_DIR)
