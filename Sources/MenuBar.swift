// MenuBar.swift — termavatar
// Menu bar UI: NSStatusItem + NSPopover with SwiftUI views.

import AppKit
import SwiftUI
import ServiceManagement

// MARK: - Design System

private enum DS {
    static let popW: CGFloat = 250
    static let popH: CGFloat = 370
    static let sheetW: CGFloat = 290
    static let rowAvatar: CGFloat = 32
    static let sheetAvatar: CGFloat = 72
    static let btnR: CGFloat = 10

    static let green = Color(nsColor: NSColor(red: 0.30, green: 0.78, blue: 0.47, alpha: 1))
    static let red = Color(nsColor: NSColor(red: 0.90, green: 0.32, blue: 0.32, alpha: 1))
    static let accent = Color.accentColor
    static let cardBg = Color.primary.opacity(0.035)
    static let hover = Color.primary.opacity(0.06)
    static let subtle = Color.primary.opacity(0.06)
}

// MARK: - Active Status Detection

private func detectActiveKeywords(configs: [String: AvatarConfig]) -> Set<String> {
    let sessionsPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent(".edgion/active_sessions.txt")
    if let content = try? String(contentsOfFile: sessionsPath, encoding: .utf8) {
        let titles = content.components(separatedBy: "\n")
        var active = Set<String>()
        for keyword in configs.keys {
            if titles.contains(where: { $0.contains(keyword) }) {
                active.insert(keyword)
            }
        }
        if !active.isEmpty { return active }
    }
    return Set(discoverWindows(configs: configs).map { $0.keyword })
}

// MARK: - Menu Bar App Delegate

final class MenuBarDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let watcher = AvatarWatcher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AvatarConfig.ensureDirectories()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "person.crop.circle.fill",
                                   accessibilityDescription: "Termavatar")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: DS.popW, height: DS.popH)
        popover.behavior = .transient

        let hostingView = NSHostingView(rootView:
            MenuBarView(watcher: watcher)
                .background(VisualEffectBackground())
        )
        popover.contentViewController = NSViewController()
        popover.contentViewController!.view = hostingView

        watcher.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher.stop()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Main View

private struct EditTarget: Identifiable {
    let id: String
    init(_ keyword: String) { self.id = keyword }
}

struct MenuBarView: View {
    let watcher: AvatarWatcher
    @State private var configs: [String: AvatarConfig] = [:]
    @State private var activeKeywords: Set<String> = []
    @State private var showingAddSheet = false
    @State private var editTarget: EditTarget? = nil
    @State private var startAtLogin: Bool = (SMAppService.mainApp.status == .enabled)

    var body: some View {
        VStack(spacing: 0) {
            header
            if configs.isEmpty {
                emptyState
            } else {
                avatarList
            }
            Spacer(minLength: 0)
            footer
        }
        .frame(width: DS.popW, height: DS.popH)
        .onAppear { reload() }
        .sheet(isPresented: $showingAddSheet) {
            AddAvatarSheet(isPresented: $showingAddSheet, onAdd: { reload() })
        }
        .sheet(item: $editTarget) { target in
            if let config = configs[target.id] {
                EditAvatarSheet(
                    config: config,
                    isPresented: Binding(
                        get: { editTarget != nil },
                        set: { if !$0 { editTarget = nil } }
                    ),
                    onSave: { reload() }
                )
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 5) {
            Text("Termavatar")
                .font(.system(size: 12, weight: .bold, design: .rounded))
            if !configs.isEmpty {
                Text("\(activeKeywords.count)/\(configs.count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
            Spacer()
            Button(action: { showingAddSheet = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DS.accent)
                    .frame(width: 22, height: 22)
                    .background(DS.accent.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 36))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DS.accent)
            VStack(spacing: 4) {
                Text("No avatars yet")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("Add avatars to identify your terminals")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Button(action: { showingAddSheet = true }) {
                Label("Add Avatar", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(DS.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Avatar List

    private var avatarList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 1) {
                ForEach(configs.keys.sorted(), id: \.self) { keyword in
                    if let config = configs[keyword] {
                        AvatarRow(
                            config: config,
                            isActive: activeKeywords.contains(keyword),
                            onEdit: { editTarget = EditTarget(keyword) },
                            onRemove: {
                                AvatarConfig.remove(keyword: keyword)
                                reload()
                            }
                        )
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Toggle(isOn: $startAtLogin) {
                Text("Start at login")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .onChange(of: startAtLogin) { _, newValue in
                if newValue {
                    try? SMAppService.mainApp.register()
                } else {
                    try? SMAppService.mainApp.unregister()
                }
                startAtLogin = (SMAppService.mainApp.status == .enabled)
            }

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
    }

    private func reload() {
        configs = AvatarConfig.loadAll()
        activeKeywords = detectActiveKeywords(configs: configs)
        watcher.poll()
    }
}

// MARK: - Avatar Row

struct AvatarRow: View {
    let config: AvatarConfig
    let isActive: Bool
    let onEdit: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            // Avatar with status dot
            ZStack(alignment: .bottomTrailing) {
                avatarImage
                    .frame(width: DS.rowAvatar, height: DS.rowAvatar)
                    .clipShape(Circle())

                Circle()
                    .fill(isActive ? DS.green : Color.gray.opacity(0.25))
                    .frame(width: 6, height: 6)
                    .overlay(Circle().stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 1))
            }

            Text(config.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 2)

            if hovering {
                HStack(spacing: 3) {
                    rowButton(icon: "pencil", action: onEdit)
                    rowButton(icon: "trash", action: onRemove, tint: DS.red.opacity(0.7))
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(hovering ? DS.hover : Color.clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onEdit() }
        .contextMenu {
            Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
            Divider()
            Button(role: .destructive, action: onRemove) { Label("Delete", systemImage: "trash") }
        }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private func rowButton(icon: String, action: @escaping () -> Void, tint: Color = .secondary) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let nsImage = NSImage(contentsOfFile: config.imagePath) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
        } else {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [DS.accent.opacity(0.2), DS.accent.opacity(0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Text(String(config.name.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.accent)
                )
        }
    }
}

// MARK: - Add Avatar Sheet

struct AddAvatarSheet: View {
    @Binding var isPresented: Bool
    let onAdd: () -> Void

    @State private var name = ""
    @State private var keyword = ""
    @State private var selectedImagePath: String?
    @State private var selectedImage: NSImage?
    @State private var errorMessage: String?
    @State private var previousName = ""

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader(icon: "person.crop.circle.badge.plus",
                        title: "New Avatar",
                        subtitle: "Add a floating avatar to your terminal")
            .padding(.bottom, 20)

            photoSection
                .padding(.bottom, 20)

            VStack(spacing: 14) {
                FormField(label: "Name", placeholder: "e.g. Jack", text: $name)
                    .onChange(of: name) { _, newValue in
                        if keyword.isEmpty || keyword == previousName {
                            keyword = newValue
                        }
                        previousName = newValue
                    }
                FormField(
                    label: "Match Keyword",
                    placeholder: "Text in terminal title",
                    text: $keyword,
                    hint: "Avatar appears when terminal title contains this"
                )
            }
            .padding(.horizontal, 24)

            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(DS.red)
                    .padding(.top, 10)
            }

            Spacer().frame(height: 22)

            SheetActions(
                onCancel: { isPresented = false },
                confirmLabel: "Add Avatar",
                onConfirm: addAvatar,
                disabled: name.isEmpty || keyword.isEmpty || selectedImagePath == nil
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: DS.sheetW)
    }

    private var photoSection: some View {
        VStack(spacing: 8) {
            ZStack {
                if let image = selectedImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: DS.sheetAvatar, height: DS.sheetAvatar)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                } else {
                    Circle()
                        .fill(DS.cardBg)
                        .frame(width: DS.sheetAvatar, height: DS.sheetAvatar)
                        .overlay(
                            Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                .foregroundStyle(Color.primary.opacity(0.1))
                        )
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.quaternary)
                        )
                }
            }
            .onTapGesture { pickImage() }

            Button("Choose Photo") { pickImage() }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(DS.accent)
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                selectedImagePath = url.path
                selectedImage = NSImage(contentsOf: url)
            }
        }
    }

    private func addAvatar() {
        guard let sourcePath = selectedImagePath else {
            errorMessage = "Please select a photo"
            return
        }
        guard let savedPath = AvatarConfig.cropCircle(sourcePath: sourcePath, name: name) else {
            errorMessage = "Failed to process image"
            return
        }
        let config = AvatarConfig(
            keyword: keyword, name: name, imagePath: savedPath,
            corner: "br", size: 90
        )
        AvatarConfig.add(config)
        onAdd()
        isPresented = false
    }
}

// MARK: - Edit Avatar Sheet

struct EditAvatarSheet: View {
    let config: AvatarConfig
    @Binding var isPresented: Bool
    let onSave: () -> Void

    @State private var name: String = ""
    @State private var keyword: String = ""
    @State private var selectedImagePath: String?
    @State private var selectedImage: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                ZStack {
                    currentPhoto
                        .frame(width: DS.sheetAvatar, height: DS.sheetAvatar)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)

                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        )
                        .offset(x: 26, y: 26)
                        .onTapGesture { pickImage() }
                }

                Text("Edit Avatar")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .padding(.top, 26)
            .padding(.bottom, 22)

            VStack(spacing: 14) {
                FormField(label: "Name", placeholder: "Display name", text: $name)
                FormField(label: "Match Keyword", placeholder: "Text in terminal title", text: $keyword)
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 22)

            SheetActions(
                onCancel: { isPresented = false },
                confirmLabel: "Save",
                onConfirm: save,
                disabled: name.isEmpty || keyword.isEmpty
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: DS.sheetW)
        .onAppear {
            name = config.name
            keyword = config.keyword
        }
    }

    @ViewBuilder
    private var currentPhoto: some View {
        if let image = selectedImage {
            Image(nsImage: image).resizable().scaledToFill()
        } else if let nsImage = NSImage(contentsOfFile: config.imagePath) {
            Image(nsImage: nsImage).resizable().scaledToFill()
        } else {
            Circle().fill(Color.gray.opacity(0.2))
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                selectedImagePath = url.path
                selectedImage = NSImage(contentsOf: url)
            }
        }
    }

    private func save() {
        AvatarConfig.remove(keyword: config.keyword)

        var imagePath = config.imagePath
        if let newPath = selectedImagePath {
            if let cropped = AvatarConfig.cropCircle(sourcePath: newPath, name: name) {
                imagePath = cropped
            }
        } else if name != config.name {
            let newPath = (AvatarConfig.avatarsDir as NSString).appendingPathComponent("\(name).png")
            let fm = FileManager.default
            try? fm.removeItem(atPath: newPath)
            if (try? fm.moveItem(atPath: config.imagePath, toPath: newPath)) != nil {
                imagePath = newPath
            }
        }

        let updated = AvatarConfig(
            keyword: keyword, name: name, imagePath: imagePath,
            corner: config.corner, size: config.size
        )
        AvatarConfig.add(updated)

        AvatarConfig.syncRenameToLiveConfig(
            oldKeyword: config.keyword,
            newKeyword: keyword,
            newName: name
        )

        onSave()
        isPresented = false
    }
}

// MARK: - Shared Components

private func sheetHeader(icon: String, title: String, subtitle: String) -> some View {
    VStack(spacing: 6) {
        ZStack {
            Circle()
                .fill(DS.accent.opacity(0.08))
                .frame(width: 52, height: 52)
            Image(systemName: icon)
                .font(.system(size: 24))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DS.accent)
        }
        Text(title)
            .font(.system(size: 16, weight: .bold, design: .rounded))
        Text(subtitle)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }
    .padding(.top, 26)
}

struct FormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var hint: String? = nil
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.4)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(DS.cardBg))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(focused ? DS.accent.opacity(0.5) : DS.subtle,
                                      lineWidth: focused ? 1.5 : 0.5)
                )
                .animation(.easeOut(duration: 0.15), value: focused)
            if let hint = hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
        }
    }
}

struct SheetActions: View {
    let onCancel: () -> Void
    let confirmLabel: String
    let onConfirm: () -> Void
    let disabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(DS.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: DS.btnR))
                    .overlay(RoundedRectangle(cornerRadius: DS.btnR).strokeBorder(DS.subtle, lineWidth: 0.5))
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.plain)

            Button(action: onConfirm) {
                Text(confirmLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(disabled ? DS.accent.opacity(0.35) : DS.accent)
                    .clipShape(RoundedRectangle(cornerRadius: DS.btnR))
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.plain)
            .disabled(disabled)
        }
    }
}

// MARK: - Visual Effect Background

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Entry Point

private var _menuBarDelegate: MenuBarDelegate?

func runMenuBarMode() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    _menuBarDelegate = MenuBarDelegate()
    app.delegate = _menuBarDelegate
    app.run()
}
