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

/// Terminal application bundle identifiers to scan for.
private let supportedBundles = [
    "com.mitchellh.ghostty", "com.googlecode.iterm2",
    "net.kovidgoyal.kitty", "com.github.wez.wezterm",
    "org.alacritty", "com.apple.Terminal",
]

/// A unique window instance: keyword + PID of the terminal app that owns it.
/// This supports multiple terminal processes (e.g. separate Ghostty instances)
/// each showing windows with the same keyword.
struct WindowInstance: Hashable {
    let keyword: String
    let pid: pid_t
}

/// Uses `NSRunningApplication.runningApplications(withBundleIdentifier:)` to
/// find all terminal processes, then queries the Accessibility API for window
/// titles. This class-method query always returns fresh results (unlike
/// `NSWorkspace.shared.runningApplications` which requires RunLoop processing).
func discoverWindows(configs: [String: AvatarConfig]) -> [WindowInstance] {
    var terminalApps: [NSRunningApplication] = []
    for bundle in supportedBundles {
        terminalApps.append(contentsOf:
            NSRunningApplication.runningApplications(withBundleIdentifier: bundle))
    }

    var found: [WindowInstance] = []
    for app in terminalApps {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        guard let axWindows = windowsRef as? [AXUIElement] else { continue }

        for axWin in axWindows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String ?? ""
            if title.isEmpty { continue }

            for (keyword, _) in configs {
                if title.contains(keyword) {
                    found.append(WindowInstance(keyword: keyword, pid: app.processIdentifier))
                    break
                }
            }
        }
    }
    return found
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

/// Tracks running overlay processes keyed by `WindowInstance` (keyword + terminal PID)
/// so each terminal process gets its own overlay.
final class OverlayManager {
    /// Maps each window instance to its overlay process PID.
    private var overlays: [WindowInstance: pid_t] = [:]
    private let overlayPath: String

    init(overlayPath: String) {
        self.overlayPath = overlayPath
    }

    /// Returns the set of window instances that currently have a running overlay.
    var activeInstances: Set<WindowInstance> {
        Set(overlays.keys)
    }

    /// Launches an overlay for the given instance if one is not already running.
    func start(instance: WindowInstance, config: AvatarConfig) {
        // If an overlay is already alive for this instance, do nothing.
        if let pid = overlays[instance], kill(pid, 0) == 0 {
            return
        }
        // Stale entry — clean up.
        overlays.removeValue(forKey: instance)

        let appName: String
        if let app = NSRunningApplication(processIdentifier: instance.pid) {
            appName = app.localizedName ?? "ghostty"
        } else {
            appName = "ghostty"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: overlayPath)
        process.arguments = [
            config.imagePath,
            "--title", instance.keyword,
            "--name", config.name,
            "--size", String(config.size),
            "--corner", config.corner,
            "--app", appName.lowercased(),
            "--pid", String(instance.pid),
        ]
        // Overlay manages its own window; suppress its stdio.
        process.standardOutput = FileHandle.nullDevice
        process.standardError  = FileHandle.nullDevice

        do {
            try process.run()
            overlays[instance] = process.processIdentifier
            log("Started '\(config.name)' (title: \(instance.keyword), pid: \(instance.pid))")
        } catch {
            log("Failed to start '\(config.name)': \(error.localizedDescription)")
        }
    }

    /// Terminates the overlay associated with the given instance.
    func stop(instance: WindowInstance) {
        guard let pid = overlays.removeValue(forKey: instance) else { return }
        kill(pid, SIGTERM)
        log("Stopped '\(instance.keyword)' (pid: \(instance.pid))")
    }

    /// Stops all running overlays (used during shutdown).
    func stopAll() {
        for instance in Array(overlays.keys) {
            stop(instance: instance)
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

    let activeInstances = Set(discoverWindows(configs: configs))

    // Start overlays for new window instances.
    for instance in activeInstances {
        if let config = configs[instance.keyword] {
            manager.start(instance: instance, config: config)
        }
    }

    // Tear down overlays whose windows have disappeared.
    for instance in manager.activeInstances {
        if !activeInstances.contains(instance) {
            manager.stop(instance: instance)
        }
    }

    RunLoop.current.run(until: Date(timeIntervalSinceNow: pollInterval))
}
