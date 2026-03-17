// Main.swift — termavatar
// Entry point: dispatches between menu bar mode and overlay mode.

import Foundation

let args = CommandLine.arguments

if args.count >= 2 && args[1] == "--overlay" {
    // Overlay mode: launched by watcher for each terminal window
    runOverlayMode(args: Array(args.dropFirst(2)))
} else if args.count >= 2 && args[1] == "--watch" {
    // Standalone watcher mode (for CLI compatibility)
    runWatcherMode()
} else {
    // Default: menu bar app
    runMenuBarMode()
}
