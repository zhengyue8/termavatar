// Overlay.swift — termavatar
// A floating circular avatar that attaches to a terminal window.
//
// Build:  swiftc -O -o termavatar Sources/Overlay.swift -framework AppKit -framework CoreGraphics -framework ApplicationServices
// Usage:  termavatar <image> [--name N] [--size N] [--corner tl|tr|bl|br] [--title keyword] [--app name] [--opacity N]
//
// Requires macOS Accessibility permission (System Settings > Privacy > Accessibility).

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Supported Terminals

/// Terminal apps recognized by default. The --app flag matches against the
/// window owner name (case-insensitive substring), so short names work fine.
let supportedTerminals = [
    "Ghostty", "iTerm2", "kitty", "WezTerm", "Alacritty", "Terminal"
]

// MARK: - Window Tracker

/// Finds a terminal window using the Accessibility API (for title matching)
/// and CGWindowList (for the Core Graphics window ID needed for z-ordering).
final class WindowTracker {
    let appName: String
    let titleKeyword: String?

    private(set) var lastFrame: CGRect = .zero
    private(set) var targetCGWindowID: CGWindowID = kCGNullWindowID

    init(appName: String, titleKeyword: String?) {
        self.appName = appName
        self.titleKeyword = titleKeyword
    }

    /// Returns the frame of the first matching window, or nil if not found.
    /// As a side effect, resolves `targetCGWindowID` for z-order placement.
    func findTargetWindow() -> CGRect? {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName?.localizedCaseInsensitiveContains(appName) == true
        }
        for app in apps {
            if let frame = findWindowInApp(pid: app.processIdentifier) {
                lastFrame = frame
                targetCGWindowID = resolveCGWindowID(matching: frame)
                return frame
            }
        }
        return nil
    }

    // MARK: Private

    /// Walk the app's AX windows looking for a title match.
    private func findWindowInApp(pid: pid_t) -> CGRect? {
        let axApp = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref)
        guard let axWindows = ref as? [AXUIElement] else { return nil }

        for axWin in axWindows {
            // Title filter (if provided)
            if let keyword = titleKeyword {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
                let title = titleRef as? String ?? ""
                guard title.contains(keyword) else { continue }
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

            // Skip tiny or zero-sized windows (e.g. menu extras)
            guard size.width > 100, size.height > 100 else { continue }

            return CGRect(origin: pos, size: size)
        }
        return nil
    }

    /// Find the CGWindowID whose bounds match the given AX frame.
    /// We need this because `window.order(.above, relativeTo:)` takes a CG ID.
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

        // Borderless, transparent window — starts offscreen
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

        // KEY: Use .normal level, not .floating. We reposition in z-order
        // each frame via window.order(.above, relativeTo: targetCGWindowID).
        // This ensures the avatar sits above the terminal but below other apps.
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let content = NSView(frame: NSRect(x: 0, y: 0, width: winW, height: winH))

        // Drop shadow backing (circle behind avatar)
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
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.current.add(timer!, forMode: .common)
        tick()
    }

    /// Called at ~30 fps. Updates overlay position and z-order.
    private func tick() {
        guard let targetFrame = tracker.findTargetWindow() else {
            // Hide when the target window is not visible
            window.alphaValue = 0
            return
        }
        window.alphaValue = opacity

        // Place overlay directly above the target window in z-order.
        // Because our window level is .normal (not .floating), the overlay
        // stays behind any other app the user switches to.
        let cgID = tracker.targetCGWindowID
        if cgID != kCGNullWindowID {
            window.order(.above, relativeTo: Int(cgID))
        }

        // Convert CG coordinates (top-left origin) to AppKit (bottom-left origin)
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

        // Only move if position actually changed (avoids unnecessary redraws)
        if abs(window.frame.origin.x - origin.x) > 0.5 ||
           abs(window.frame.origin.y - origin.y) > 0.5 {
            window.setFrameOrigin(origin)
        }
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
      termavatar <image> [options]

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

    NOTES
      Requires Accessibility permission (System Settings > Privacy > Accessibility).
      Right-click the avatar to quit.

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
