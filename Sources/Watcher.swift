// Watcher.swift — termavatar
// Monitors terminal windows and spawns/kills overlay processes.
// Used as a class by the menu bar app, or standalone via runWatcherMode().

import AppKit
import ApplicationServices
import Foundation

// MARK: - Logging

func watcherLog(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    let ts = formatter.string(from: Date())
    print("[\(ts)] \(message)")
    fflush(stdout)
}

// MARK: - Window Discovery

private let supportedBundles = [
    "com.mitchellh.ghostty", "com.googlecode.iterm2",
    "net.kovidgoyal.kitty", "com.github.wez.wezterm",
    "org.alacritty", "com.apple.Terminal",
]

/// A unique window instance: keyword + PID of the terminal app that owns it.
struct WindowInstance: Hashable {
    let keyword: String
    let pid: pid_t
}

/// Uses NSRunningApplication.runningApplications(withBundleIdentifier:) to
/// find all terminal processes, then queries the Accessibility API for window
/// titles. This class-method query always returns fresh results.
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

// MARK: - AvatarWatcher

/// Manages the lifecycle of overlay processes. Can be used by the menu bar app
/// (timer-driven) or standalone (loop-driven via runWatcherMode).
final class AvatarWatcher {
    private var overlays: [WindowInstance: pid_t] = [:]
    private var configs: [String: AvatarConfig] = [:]
    private var lastConfigReload = Date()
    private let configReloadInterval: TimeInterval = 10.0
    private var timer: Timer?

    /// The path to the binary used for overlay processes.
    /// In the .app bundle this is the app's own executable (invoked with --overlay).
    /// Standalone, it looks for termavatar-overlay next to itself.
    var overlayBinaryPath: String = ""
    var overlayUseSelfBinary = false

    var activeCount: Int { overlays.count }

    func start() {
        if overlayBinaryPath.isEmpty {
            if let execPath = Bundle.main.executablePath {
                overlayBinaryPath = execPath
                overlayUseSelfBinary = true
            } else {
                let execURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardized
                overlayBinaryPath = execURL.deletingLastPathComponent()
                    .appendingPathComponent("termavatar-overlay").path
            }
        }

        configs = AvatarConfig.loadAll()
        watcherLog("Loaded \(configs.count) avatar(s): \(configs.keys.sorted().joined(separator: ", "))")

        // Run first poll immediately
        poll()

        // Schedule timer for subsequent polls
        timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        stopAll()
    }

    func poll() {
        // Hot-reload config periodically
        if Date().timeIntervalSince(lastConfigReload) >= configReloadInterval {
            let newConfigs = AvatarConfig.loadAll()
            if newConfigs.keys.sorted() != configs.keys.sorted() {
                watcherLog("Config reloaded: \(newConfigs.count) entry/entries")
            }
            configs = newConfigs
            lastConfigReload = Date()
        }

        let activeInstances = Set(discoverWindows(configs: configs))

        // Start overlays for new window instances
        for instance in activeInstances {
            if let config = configs[instance.keyword] {
                startOverlay(instance: instance, config: config)
            }
        }

        // Stop overlays for disappeared window instances
        for instance in Array(overlays.keys) {
            if !activeInstances.contains(instance) {
                stopOverlay(instance: instance)
            }
        }
    }

    private func startOverlay(instance: WindowInstance, config: AvatarConfig) {
        if let pid = overlays[instance], kill(pid, 0) == 0 {
            return
        }
        overlays.removeValue(forKey: instance)

        let appName: String
        if let app = NSRunningApplication(processIdentifier: instance.pid) {
            appName = app.localizedName ?? "ghostty"
        } else {
            appName = "ghostty"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: overlayBinaryPath)

        var args: [String] = []
        if overlayUseSelfBinary {
            args.append("--overlay")
        }
        args += [
            config.imagePath,
            "--title", instance.keyword,
            "--name", config.name,
            "--size", String(config.size),
            "--corner", config.corner,
            "--app", appName.lowercased(),
            "--pid", String(instance.pid),
        ]
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            overlays[instance] = process.processIdentifier
            watcherLog("Started '\(config.name)' (title: \(instance.keyword), pid: \(instance.pid))")
        } catch {
            watcherLog("Failed to start '\(config.name)': \(error.localizedDescription)")
        }
    }

    private func stopOverlay(instance: WindowInstance) {
        guard let pid = overlays.removeValue(forKey: instance) else { return }
        kill(pid, SIGTERM)
        watcherLog("Stopped '\(instance.keyword)' (pid: \(instance.pid))")
    }

    private func stopAll() {
        for instance in Array(overlays.keys) {
            stopOverlay(instance: instance)
        }
    }
}

// MARK: - Standalone Watcher Entry Point

// Global reference so signal handlers can stop the watcher cleanly.
private var _standaloneWatcher: AvatarWatcher?

/// Runs the watcher as a standalone daemon (used by the CLI `termavatar watch`).
func runWatcherMode() {
    let watcher = AvatarWatcher()
    _standaloneWatcher = watcher

    watcherLog("termavatar watcher starting")
    watcher.start()

    // Graceful shutdown: stop child overlays before exiting.
    signal(SIGINT)  { _ in _standaloneWatcher?.stop(); exit(0) }
    signal(SIGTERM) { _ in _standaloneWatcher?.stop(); exit(0) }
    RunLoop.current.run()
}
