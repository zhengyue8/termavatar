// Watcher.swift — termavatar watcher daemon
//
// Monitors terminal window titles via the macOS Accessibility API and spawns
// overlay processes when a window title matches a configured keyword.
//
// Config file:  ~/.termavatar/config
// Format:       keyword|name|image_path|corner|size
//
// Build:  swiftc -o termavatar-watcher Watcher.swift -framework AppKit
// Run:    ./termavatar-watcher

import AppKit
import ApplicationServices
import Foundation

// MARK: - Logging

/// Prints a timestamped message and flushes stdout so log output is never
/// buffered (important when the daemon's stdout is piped to a file).
private func log(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    let ts = formatter.string(from: Date())
    print("[\(ts)] \(message)")
    fflush(stdout)
}

// MARK: - Configuration Model

/// A single avatar entry parsed from the config file.
struct AvatarConfig {
    let name: String
    let imagePath: String
    let corner: String   // e.g. "tl", "tr", "bl", "br"
    let size: Int
}

/// Reads `~/.termavatar/config` and returns a keyword-keyed dictionary.
///
/// File format (one entry per line):
/// ```
/// keyword|display_name|image_path|corner|size
/// ```
/// - Lines starting with `#` are comments.
/// - Empty or whitespace-only lines are skipped.
/// - `image_path` may be absolute or relative to `~/.termavatar/`.
/// - `size` is optional and defaults to 90.
func loadConfig() -> [String: AvatarConfig] {
    let configDir = NSString("~/.termavatar").expandingTildeInPath
    let configPath = (configDir as NSString).appendingPathComponent("config")

    guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
        log("Could not read config at \(configPath)")
        return [:]
    }

    var configs: [String: AvatarConfig] = [:]

    for line in content.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

        let parts = trimmed.split(separator: "|", maxSplits: 4).map(String.init)
        guard parts.count >= 4 else {
            log("Skipping malformed config line: \(trimmed)")
            continue
        }

        let keyword   = parts[0]
        let name      = parts[1]
        var imagePath  = parts[2]
        let corner    = parts[3]
        let size      = parts.count >= 5 ? (Int(parts[4]) ?? 90) : 90

        // Resolve relative image paths against ~/.termavatar/
        if !imagePath.hasPrefix("/") && !imagePath.hasPrefix("~") {
            imagePath = (configDir as NSString).appendingPathComponent(imagePath)
        } else if imagePath.hasPrefix("~") {
            imagePath = NSString(string: imagePath).expandingTildeInPath
        }

        configs[keyword] = AvatarConfig(
            name: name,
            imagePath: imagePath,
            corner: corner,
            size: size
        )
    }

    return configs
}

// MARK: - Window Discovery

/// Terminal application bundle-name substrings to scan for.
private let terminalAppNames = [
    "ghostty",
    "iterm",
    "kitty",
    "wezterm",
    "alacritty",
    "terminal",
]

/// Represents a terminal window found via the Accessibility API.
struct TerminalWindow {
    let title: String
    let appName: String   // localised application name
}

/// Queries the Accessibility API for all visible terminal windows and returns
/// their titles along with the owning application name.
func getTerminalWindows() -> [TerminalWindow] {
    let running = NSWorkspace.shared.runningApplications

    // Filter to known terminal emulators.
    let terminalApps = running.filter { app in
        guard let name = app.localizedName?.lowercased() else { return false }
        return terminalAppNames.contains { name.contains($0) }
    }

    var results: [TerminalWindow] = []

    for app in terminalApps {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            axApp,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )
        guard status == .success, let windows = windowsRef as? [AXUIElement] else {
            continue
        }

        for window in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            if let title = titleRef as? String, !title.isEmpty {
                results.append(TerminalWindow(
                    title: title,
                    appName: app.localizedName ?? "unknown"
                ))
            }
        }
    }

    return results
}

// MARK: - Overlay Process Management

/// Resolves the path to `termavatar-overlay`, which is expected to live in
/// the same directory as the running watcher binary.
func resolveOverlayPath() -> String {
    let executablePath = CommandLine.arguments[0]
    let executableURL = URL(fileURLWithPath: executablePath).standardized
    let directory = executableURL.deletingLastPathComponent()
    return directory.appendingPathComponent("termavatar-overlay").path
}

/// Tracks running overlay processes keyed by a unique window identifier
/// (combination of keyword and window title) so we can stop them when the
/// matching window disappears.
final class OverlayManager {
    /// Maps a tracking key (keyword) to the PID of its overlay process.
    private var overlays: [String: pid_t] = [:]
    private let overlayPath: String

    init(overlayPath: String) {
        self.overlayPath = overlayPath
    }

    /// Returns the set of keywords that currently have a running overlay.
    var activeKeywords: Set<String> {
        Set(overlays.keys)
    }

    /// Launches an overlay for the given keyword if one is not already running.
    func start(keyword: String, config: AvatarConfig, appName: String) {
        // If an overlay is already alive for this keyword, do nothing.
        if let pid = overlays[keyword], kill(pid, 0) == 0 {
            return
        }
        // Stale entry — clean up.
        overlays.removeValue(forKey: keyword)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: overlayPath)
        process.arguments = [
            config.imagePath,
            "--title", keyword,
            "--name", config.name,
            "--size", String(config.size),
            "--corner", config.corner,
            "--app", appName.lowercased(),
        ]
        // Overlay manages its own window; suppress its stdio.
        process.standardOutput = FileHandle.nullDevice
        process.standardError  = FileHandle.nullDevice

        do {
            try process.run()
            overlays[keyword] = process.processIdentifier
            log("Started overlay '\(config.name)' for keyword '\(keyword)' (pid \(process.processIdentifier))")
        } catch {
            log("Failed to launch overlay for '\(config.name)': \(error.localizedDescription)")
        }
    }

    /// Terminates the overlay associated with the given keyword.
    func stop(keyword: String) {
        guard let pid = overlays.removeValue(forKey: keyword) else { return }
        kill(pid, SIGTERM)
        log("Stopped overlay for keyword '\(keyword)' (pid \(pid))")
    }

    /// Stops all running overlays (used during shutdown).
    func stopAll() {
        for keyword in Array(overlays.keys) {
            stop(keyword: keyword)
        }
    }
}

// MARK: - Main Entry Point

log("termavatar watcher starting")

// Resolve the companion overlay binary path.
let overlayPath = resolveOverlayPath()
guard FileManager.default.isExecutableFile(atPath: overlayPath) else {
    log("ERROR: overlay binary not found at \(overlayPath)")
    exit(1)
}
log("Overlay binary: \(overlayPath)")

// Initial config load.
var configs = loadConfig()
if configs.isEmpty {
    log("Warning: no entries found in ~/.termavatar/config")
} else {
    log("Loaded \(configs.count) config(s): \(configs.keys.sorted().joined(separator: ", "))")
}

let manager = OverlayManager(overlayPath: overlayPath)

// Graceful shutdown: kill child overlays when the watcher is terminated.
signal(SIGINT)  { _ in manager.stopAll(); exit(0) }
signal(SIGTERM) { _ in manager.stopAll(); exit(0) }

// Timing constants.
let pollInterval: TimeInterval = 2.0          // window check frequency
let configReloadInterval: TimeInterval = 10.0 // config hot-reload frequency
var lastConfigReload = Date()

log("Watching terminal windows every \(Int(pollInterval))s (config reload every \(Int(configReloadInterval))s)")

// MARK: Main Loop

while true {
    // Hot-reload config periodically so users can edit without restarting.
    if Date().timeIntervalSince(lastConfigReload) >= configReloadInterval {
        let newConfigs = loadConfig()
        if newConfigs.keys.sorted() != configs.keys.sorted() {
            log("Config reloaded: \(newConfigs.count) entry/entries")
        }
        configs = newConfigs
        lastConfigReload = Date()
    }

    // Discover all terminal windows.
    let windows = getTerminalWindows()

    // Track which keywords matched a visible window this cycle.
    var matchedKeywords = Set<String>()

    for (keyword, config) in configs {
        for window in windows {
            if window.title.contains(keyword) {
                matchedKeywords.insert(keyword)
                manager.start(keyword: keyword, config: config, appName: window.appName)
                break  // one match per keyword is enough
            }
        }
    }

    // Tear down overlays whose windows have disappeared.
    for keyword in manager.activeKeywords {
        if !matchedKeywords.contains(keyword) {
            manager.stop(keyword: keyword)
        }
    }

    Thread.sleep(forTimeInterval: pollInterval)
}
