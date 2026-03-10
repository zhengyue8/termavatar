// Overlay.swift — termavatar
// A floating circular avatar that attaches to a terminal window.
//
// Features:
//   - Tracks terminal window position at 10 fps via Accessibility API
//   - Z-orders above terminal but below other apps (.normal level)
//   - Detects minimized terminals; parks avatar on desktop (draggable)
//   - Click parked avatar to un-minimize and restore its terminal
//   - Right-click avatar to quit
//
// Build:  swiftc -O -o termavatar-overlay Sources/Overlay.swift -framework AppKit -framework CoreGraphics -framework ApplicationServices
// Usage:  termavatar-overlay <image> [--name N] [--size N] [--corner tl|tr|bl|br] [--title keyword] [--app name] [--opacity N]
//
// Requires macOS Accessibility permission (System Settings > Privacy > Accessibility).

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Supported Terminals

let supportedTerminals = [
    "Ghostty", "iTerm2", "kitty", "WezTerm", "Alacritty", "Terminal"
]

// MARK: - Window State

enum WindowState {
    case visible(frame: CGRect)
    case minimized
    case notFound
}

// MARK: - Minimized Avatar Dock

/// When terminals are minimized, avatars park on a secondary screen (or main
/// if only one display). Multiple avatars coordinate positions via slot files
/// in ~/.termavatar/dock/.
struct MinimizedDock {
    static let dockDir = (NSHomeDirectory() as NSString).appendingPathComponent(".termavatar/dock")
    static let spacing: CGFloat = 110
    static let bottomMargin: CGFloat = 80

    /// Prefers secondary (non-built-in) screen for parking avatars.
    static var dockScreen: NSScreen {
        let screens = NSScreen.screens
        if screens.count > 1 {
            for s in screens where s != NSScreen.main {
                return s
            }
        }
        return NSScreen.main ?? screens[0]
    }

    /// Claim a slot and return the desktop position (AppKit coordinates).
    static func claimSlot(keyword: String) -> NSPoint? {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dockDir, withIntermediateDirectories: true)
        let slotFile = (dockDir as NSString).appendingPathComponent(keyword)
        if !fm.fileExists(atPath: slotFile) {
            fm.createFile(atPath: slotFile, contents: nil)
        }

        guard let files = try? fm.contentsOfDirectory(atPath: dockDir) else { return nil }
        let sorted = files.sorted()
        guard let idx = sorted.firstIndex(of: keyword) else { return nil }

        let screen = dockScreen
        let frame = screen.visibleFrame
        let totalWidth = CGFloat(sorted.count) * spacing
        let startX = frame.origin.x + (frame.width - totalWidth) / 2

        return NSPoint(
            x: startX + CGFloat(idx) * spacing,
            y: frame.origin.y + bottomMargin
        )
    }

    /// Release slot when terminal is no longer minimized.
    static func releaseSlot(keyword: String) {
        let slotFile = (dockDir as NSString).appendingPathComponent(keyword)
        try? FileManager.default.removeItem(atPath: slotFile)
    }
}

// MARK: - Window Tracker

/// Finds a terminal window using the Accessibility API (for title matching)
/// and CGWindowList (for the Core Graphics window ID needed for z-ordering).
/// Also stores the AXUIElement so we can un-minimize a specific window.
final class WindowTracker {
    let appName: String
    let titleKeyword: String?

    private(set) var lastFrame: CGRect = .zero
    private(set) var targetCGWindowID: CGWindowID = kCGNullWindowID
    private(set) var matchedAXWindow: AXUIElement?
    private(set) var matchedAppPID: pid_t = 0

    init(appName: String, titleKeyword: String?) {
        self.appName = appName
        self.titleKeyword = titleKeyword
    }

    /// Returns the window state: visible with frame, minimized, or not found.
    func getWindowState() -> WindowState {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName?.localizedCaseInsensitiveContains(appName) == true
        }

        for app in apps {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var ref: CFTypeRef?
            AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref)
            guard let axWindows = ref as? [AXUIElement] else { continue }

            for axWin in axWindows {
                // Title filter
                if let keyword = titleKeyword {
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
                    let title = titleRef as? String ?? ""
                    guard title.contains(keyword) else { continue }
                }

                // Remember for un-minimize
                matchedAXWindow = axWin
                matchedAppPID = app.processIdentifier

                // Check minimized
                var minimizedRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXMinimizedAttribute as CFString, &minimizedRef)
                if let minimized = minimizedRef as? Bool, minimized {
                    return .minimized
                }

                // Read position and size
                var posRef: CFTypeRef?
                var sizeRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &posRef)
                AXUIElementCopyAttributeValue(axWin, kAXSizeAttribute as CFString, &sizeRef)
                guard let pv = posRef, let sv = sizeRef else { continue }

                var pos = CGPoint.zero
                var size = CGSize.zero
                AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
                AXValueGetValue(sv as! AXValue, .cgSize, &size)

                guard size.width > 100, size.height > 100 else { continue }

                let frame = CGRect(origin: pos, size: size)
                lastFrame = frame
                targetCGWindowID = resolveCGWindowID(matching: frame)

                return .visible(frame: frame)
            }
        }
        return .notFound
    }

    /// Un-minimize the matched window, raise it, and bring its app to front.
    func unminimize() {
        guard let axWin = matchedAXWindow else { return }
        AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, false as CFTypeRef)
        AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
        if let app = NSRunningApplication(processIdentifier: matchedAppPID) {
            app.activate()
        }
    }

    // MARK: Private

    private func resolveCGWindowID(matching frame: CGRect) -> CGWindowID {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return kCGNullWindowID
        }

        let tolerance: CGFloat = 3
        for info in list {
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  owner.localizedCaseInsensitiveContains(appName),
                  let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let w = bounds["Width"] as? CGFloat,
                  let h = bounds["Height"] as? CGFloat,
                  (info[kCGWindowLayer as String] as? Int) == 0
            else { continue }

            if abs(x - frame.origin.x) < tolerance &&
               abs(y - frame.origin.y) < tolerance &&
               abs(w - frame.width) < tolerance &&
               abs(h - frame.height) < tolerance {
                return wid
            }
        }
        return kCGNullWindowID
    }
}

// MARK: - Draggable Content View

/// Handles mouse drag (to reposition parked avatar) and click (to un-minimize).
final class DraggableView: NSView {
    weak var overlayApp: OverlayApp?
    private var dragStart: NSPoint?
    private var windowStart: NSPoint?
    private var didDrag = false

    override func mouseDown(with event: NSEvent) {
        guard overlayApp?.isParkedOnDesktop == true else { return }
        dragStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard overlayApp?.isParkedOnDesktop == true,
              let start = dragStart, let winStart = windowStart else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - start.x
        let dy = current.y - start.y
        if abs(dx) > 3 || abs(dy) > 3 { didDrag = true }
        window?.setFrameOrigin(NSPoint(x: winStart.x + dx, y: winStart.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        guard overlayApp?.isParkedOnDesktop == true else { return }
        if didDrag {
            if let origin = window?.frame.origin {
                overlayApp?.userParkedPosition = origin
            }
        } else {
            overlayApp?.unminimizeTerminal()
        }
        dragStart = nil
        windowStart = nil
    }
}

// MARK: - Overlay Application Delegate

final class OverlayApp: NSObject, NSApplicationDelegate {

    // Configuration (set once at init)
    private let imagePath: String
    private let agentName: String
    private let avatarSize: CGFloat
    private let corner: String
    private let opacity: CGFloat
    private let appTarget: String
    private let titleKeyword: String?
    private let margin: CGFloat = 8

    // Runtime state
    private var window: NSWindow!
    private var tracker: WindowTracker!
    private var timer: Timer?

    // Minimized dock state
    fileprivate var isParkedOnDesktop = false
    /// User's preferred position when parked (set by dragging). Nil = use dock default.
    var userParkedPosition: NSPoint? = nil

    init(imagePath: String, agentName: String, avatarSize: CGFloat,
         corner: String, opacity: CGFloat, appTarget: String, titleKeyword: String?) {
        self.imagePath = imagePath
        self.agentName = agentName
        self.avatarSize = avatarSize
        self.corner = corner
        self.opacity = opacity
        self.appTarget = appTarget
        self.titleKeyword = titleKeyword
        super.init()
    }

    // MARK: NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let image = NSImage(contentsOfFile: imagePath) else {
            fputs("termavatar: cannot load image at \(imagePath)\n", stderr)
            NSApp.terminate(nil)
            return
        }

        tracker = WindowTracker(appName: appTarget, titleKeyword: titleKeyword)
        buildWindow(image: image)
        startTracking()
    }

    // MARK: Window Construction

    private func buildWindow(image: NSImage) {
        let padding: CGFloat = 6
        let labelHeight: CGFloat = agentName.isEmpty ? 0 : 20
        let winW = avatarSize + padding * 2
        let winH = avatarSize + labelHeight + padding * 2

        window = NSWindow(
            contentRect: NSRect(x: -9999, y: -9999, width: winW, height: winH),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = false
        window.alphaValue = opacity
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let content = DraggableView(frame: NSRect(x: 0, y: 0, width: winW, height: winH))
        content.overlayApp = self

        // Drop shadow backing
        let shadowView = NSView(frame: NSRect(x: padding, y: labelHeight + padding,
                                              width: avatarSize, height: avatarSize))
        shadowView.wantsLayer = true
        shadowView.layer?.cornerRadius = avatarSize / 2
        shadowView.layer?.backgroundColor = NSColor.white.cgColor
        shadowView.layer?.shadowColor = NSColor.black.cgColor
        shadowView.layer?.shadowOpacity = 0.4
        shadowView.layer?.shadowOffset = CGSize(width: 0, height: -2)
        shadowView.layer?.shadowRadius = 5
        content.addSubview(shadowView)

        // Circular avatar image
        let imageView = NSImageView(frame: NSRect(x: padding, y: labelHeight + padding,
                                                  width: avatarSize, height: avatarSize))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = avatarSize / 2
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 2
        imageView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.5).cgColor
        content.addSubview(imageView)

        // Name label below avatar
        if !agentName.isEmpty {
            let label = NSTextField(frame: NSRect(x: 0, y: padding - 2,
                                                  width: winW, height: labelHeight))
            label.stringValue = agentName
            label.isEditable = false
            label.isBordered = false
            label.backgroundColor = .clear
            label.alignment = .center
            label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            label.textColor = NSColor(white: 1.0, alpha: 0.95)

            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.8)
            shadow.shadowOffset = CGSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 3
            label.shadow = shadow
            content.addSubview(label)
        }

        // Right-click to quit
        let rightClick = NSClickGestureRecognizer(target: self, action: #selector(quit))
        rightClick.buttonMask = 0x2
        content.addGestureRecognizer(rightClick)

        window.contentView = content
        window.orderFrontRegardless()
    }

    // MARK: Position Tracking

    private func startTracking() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 10.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.current.add(timer!, forMode: .common)
        tick()
    }

    /// Called at ~10 fps. Updates overlay position and z-order.
    private func tick() {
        let state = tracker.getWindowState()

        switch state {
        case .notFound:
            window.alphaValue = 0
            if isParkedOnDesktop {
                MinimizedDock.releaseSlot(keyword: titleKeyword ?? agentName)
                isParkedOnDesktop = false
            }

        case .minimized:
            if !isParkedOnDesktop {
                isParkedOnDesktop = true
                window.level = .floating
                window.alphaValue = opacity
                if let savedPos = userParkedPosition {
                    window.setFrameOrigin(savedPos)
                } else if let dockPos = MinimizedDock.claimSlot(keyword: titleKeyword ?? agentName) {
                    window.setFrameOrigin(dockPos)
                }
                window.orderFrontRegardless()
            }

        case .visible(let targetFrame):
            if isParkedOnDesktop {
                MinimizedDock.releaseSlot(keyword: titleKeyword ?? agentName)
                isParkedOnDesktop = false
                window.level = .normal
            }

            window.alphaValue = opacity

            let cgID = tracker.targetCGWindowID
            if cgID != kCGNullWindowID {
                window.order(.above, relativeTo: Int(cgID))
            }

            guard let screen = NSScreen.main else { return }
            let screenH = screen.frame.height
            let wSize = window.frame.size
            let nsTargetY = screenH - targetFrame.origin.y - targetFrame.height

            let origin: NSPoint
            switch corner.lowercased() {
            case "tl", "top-left":
                origin = NSPoint(
                    x: targetFrame.origin.x + margin,
                    y: nsTargetY + targetFrame.height - wSize.height - margin)
            case "tr", "top-right":
                origin = NSPoint(
                    x: targetFrame.origin.x + targetFrame.width - wSize.width - margin,
                    y: nsTargetY + targetFrame.height - wSize.height - margin)
            case "bl", "bottom-left":
                origin = NSPoint(
                    x: targetFrame.origin.x + margin,
                    y: nsTargetY + margin)
            default: // "br", "bottom-right"
                origin = NSPoint(
                    x: targetFrame.origin.x + targetFrame.width - wSize.width - margin,
                    y: nsTargetY + margin)
            }

            if abs(window.frame.origin.x - origin.x) > 0.5 ||
               abs(window.frame.origin.y - origin.y) > 0.5 {
                window.setFrameOrigin(origin)
            }
        }
    }

    /// Called by DraggableView when user clicks the parked avatar.
    func unminimizeTerminal() {
        tracker.unminimize()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - CLI Argument Parsing

struct Config {
    var imagePath: String = ""
    var name: String = ""
    var size: CGFloat = 80
    var corner: String = "br"
    var opacity: CGFloat = 0.92
    var app: String = "ghostty"
    var title: String? = nil
}

func printUsage() -> Never {
    let terminals = supportedTerminals.joined(separator: ", ")
    fputs("""
    termavatar — floating avatar for terminal windows

    USAGE
      termavatar-overlay <image> [options]

    OPTIONS
      --name <text>       Label shown below the avatar
      --size <px>         Avatar diameter in points (default: 80)
      --corner <pos>      tl, tr, bl, br (default: br)
      --opacity <0-1>     Window opacity (default: 0.92)
      --app <name>        Terminal app to attach to (default: ghostty)
      --title <keyword>   Only match windows whose title contains this string
      -h, --help          Show this help

    SUPPORTED TERMINALS
      \(terminals)

    INTERACTIONS
      - Drag the avatar when its terminal is minimized to reposition it.
      - Click a parked avatar to un-minimize and restore its terminal.
      - Right-click the avatar to quit.

    NOTES
      Requires Accessibility permission (System Settings > Privacy > Accessibility).

    """, stderr)
    exit(0)
}

func parseArgs() -> Config {
    let args = CommandLine.arguments
    guard args.count >= 2 else {
        fputs("termavatar: missing image path. Use --help for usage.\n", stderr)
        exit(1)
    }
    if args[1] == "--help" || args[1] == "-h" { printUsage() }

    var cfg = Config()
    cfg.imagePath = (args[1] as NSString).expandingTildeInPath

    var i = 2
    while i < args.count {
        switch args[i] {
        case "--name"    where i + 1 < args.count: cfg.name    = args[i+1]; i += 2
        case "--size"    where i + 1 < args.count: cfg.size    = CGFloat(Double(args[i+1]) ?? 80); i += 2
        case "--corner"  where i + 1 < args.count: cfg.corner  = args[i+1]; i += 2
        case "--opacity" where i + 1 < args.count: cfg.opacity = CGFloat(Double(args[i+1]) ?? 0.92); i += 2
        case "--app"     where i + 1 < args.count: cfg.app     = args[i+1]; i += 2
        case "--title"   where i + 1 < args.count: cfg.title   = args[i+1]; i += 2
        case "--help", "-h": printUsage()
        default:
            fputs("termavatar: unknown option '\(args[i])'\n", stderr)
            i += 1
        }
    }
    return cfg
}

// MARK: - Main

let cfg = parseArgs()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // No dock icon

let delegate = OverlayApp(
    imagePath: cfg.imagePath,
    agentName: cfg.name,
    avatarSize: cfg.size,
    corner: cfg.corner,
    opacity: cfg.opacity,
    appTarget: cfg.app,
    titleKeyword: cfg.title
)
app.delegate = delegate
app.run()
