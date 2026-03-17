// MenuBar.swift — termavatar
// Menu bar UI: NSStatusItem + NSPopover with SwiftUI views.

import AppKit
import SwiftUI
import ServiceManagement

// MARK: - Design Tokens

private enum Design {
    // Spacing
    static let popoverWidth: CGFloat = 320
    static let popoverHeight: CGFloat = 440
    static let sheetWidth: CGFloat = 340

    // Avatar
    static let avatarSize: CGFloat = 44
    static let avatarSizeLarge: CGFloat = 72

    // Corner radius
    static let cardRadius: CGFloat = 10

    // Colors
    static let activeGreen = Color(nsColor: NSColor(red: 0.30, green: 0.78, blue: 0.47, alpha: 1.0))
    static let hoverBg = Color.primary.opacity(0.06)
    static let subtleBorder = Color.primary.opacity(0.08)
    static let dangerRed = Color(nsColor: NSColor(red: 0.92, green: 0.34, blue: 0.34, alpha: 1.0))
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
        popover.contentSize = NSSize(width: Design.popoverWidth, height: Design.popoverHeight)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(watcher: watcher)
        )

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

struct MenuBarView: View {
    let watcher: AvatarWatcher
    @State private var configs: [String: AvatarConfig] = [:]
    @State private var showingAddSheet = false
    @State private var editTarget: EditTarget? = nil
    @State private var startAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var confirmDeleteKeyword: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5).padding(.horizontal, 16)

            if configs.isEmpty {
                emptyState
            } else {
                avatarList
            }

            Divider().opacity(0.5).padding(.horizontal, 16)
            footer
        }
        .frame(width: Design.popoverWidth, height: Design.popoverHeight)
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Termavatar")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("\(configs.count) avatar\(configs.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { showingAddSheet = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Add avatar")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 72, height: 72)
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor.opacity(0.6))
            }
            VStack(spacing: 4) {
                Text("No avatars yet")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Add your first avatar to get started")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Button("Add Avatar") { showingAddSheet = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Avatar List

    private var avatarList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(configs.keys.sorted(), id: \.self) { keyword in
                    if let config = configs[keyword] {
                        AvatarRow(
                            config: config,
                            isConfirmingDelete: confirmDeleteKeyword == keyword,
                            onEdit: { editTarget = EditTarget(keyword) },
                            onRemove: {
                                if confirmDeleteKeyword == keyword {
                                    AvatarConfig.remove(keyword: keyword)
                                    confirmDeleteKeyword = nil
                                    reload()
                                } else {
                                    confirmDeleteKeyword = keyword
                                }
                            },
                            onCancelDelete: { confirmDeleteKeyword = nil }
                        )
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $startAtLogin) {
                Label("Login", systemImage: "arrow.right.circle")
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

            HStack(spacing: 4) {
                Circle()
                    .fill(Design.activeGreen)
                    .frame(width: 7, height: 7)
                    .shadow(color: Design.activeGreen.opacity(0.5), radius: 3)
                Text("Active")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Quit Termavatar")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func reload() {
        configs = AvatarConfig.loadAll()
        watcher.poll()
    }
}

// Wrapper for .sheet(item:) binding — avoids fragile String: Identifiable conformance.
private struct EditTarget: Identifiable {
    let id: String
    init(_ keyword: String) { self.id = keyword }
}

// MARK: - Avatar Row

struct AvatarRow: View {
    let config: AvatarConfig
    let isConfirmingDelete: Bool
    let onEdit: () -> Void
    let onRemove: () -> Void
    let onCancelDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            // Avatar image with status ring
            ZStack {
                Circle()
                    .fill(Design.activeGreen.opacity(0.2))
                    .frame(width: Design.avatarSize + 4, height: Design.avatarSize + 4)
                avatarImage
                    .frame(width: Design.avatarSize, height: Design.avatarSize)
                    .clipShape(Circle())
            }

            // Name and keyword
            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if config.keyword != config.name {
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                            .font(.system(size: 8))
                        Text(config.keyword)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }

            Spacer()

            // Actions
            if isConfirmingDelete {
                // Delete confirmation inline
                HStack(spacing: 6) {
                    Button(action: onCancelDelete) {
                        Text("No")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 22)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)

                    Button(action: onRemove) {
                        Text("Delete")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 22)
                            .background(Design.dangerRed)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .opacity
                ))
            } else if hovering {
                HStack(spacing: 4) {
                    iconButton(icon: "pencil", action: onEdit)
                    iconButton(icon: "trash", action: onRemove, tint: Design.dangerRed.opacity(0.8))
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hovering ? Design.hoverBg : Color.clear)
                .padding(.horizontal, 8)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .animation(.easeInOut(duration: 0.2), value: isConfirmingDelete)
    }

    private func iconButton(icon: String, action: @escaping () -> Void, tint: Color = .secondary) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(0.06))
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
                        colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.15)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Text(String(config.name.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
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
            // Sheet header
            VStack(spacing: 4) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                Text("New Avatar")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Add a floating avatar to your terminal")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Photo picker
            photoSection
                .padding(.bottom, 20)

            // Form fields
            VStack(spacing: 14) {
                FormField(label: "Name", placeholder: "e.g. Jack", text: $name)
                    .onChange(of: name) { _, newValue in
                        if keyword.isEmpty || keyword == previousName {
                            keyword = newValue
                        }
                        previousName = newValue
                    }

                FormField(
                    label: "Window Title Keyword",
                    placeholder: "Text to match in terminal title",
                    text: $keyword,
                    hint: "The avatar appears when a terminal title contains this text"
                )
            }
            .padding(.horizontal, 24)

            if let error = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(error)
                        .font(.system(size: 11))
                }
                .foregroundColor(Design.dangerRed)
                .padding(.top, 10)
            }

            Spacer().frame(height: 20)

            // Actions
            HStack(spacing: 10) {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button(action: addAvatar) {
                    Text("Add Avatar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            (name.isEmpty || keyword.isEmpty || selectedImagePath == nil)
                                ? Color.accentColor.opacity(0.4)
                                : Color.accentColor
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.plain)
                .disabled(name.isEmpty || keyword.isEmpty || selectedImagePath == nil)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: Design.sheetWidth)
    }

    private var photoSection: some View {
        VStack(spacing: 10) {
            ZStack {
                if let image = selectedImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: Design.avatarSizeLarge, height: Design.avatarSizeLarge)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                } else {
                    Circle()
                        .fill(Color.primary.opacity(0.04))
                        .frame(width: Design.avatarSizeLarge, height: Design.avatarSizeLarge)
                        .overlay(
                            Circle()
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                .foregroundStyle(Color.primary.opacity(0.15))
                        )
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.tertiary)
                        )
                }
            }
            .onTapGesture { pickImage() }

            Button("Choose Photo") { pickImage() }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
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
            // Sheet header with current photo
            VStack(spacing: 12) {
                ZStack {
                    currentPhoto
                        .frame(width: Design.avatarSizeLarge, height: Design.avatarSizeLarge)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

                    // Camera overlay button
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 26, height: 26)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        )
                        .offset(x: 24, y: 24)
                        .onTapGesture { pickImage() }
                }

                Text("Edit Avatar")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Form fields
            VStack(spacing: 14) {
                FormField(label: "Name", placeholder: "Display name", text: $name)
                FormField(label: "Window Title Keyword", placeholder: "Text to match", text: $keyword)
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 20)

            // Actions
            HStack(spacing: 10) {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button(action: save) {
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            (name.isEmpty || keyword.isEmpty)
                                ? Color.accentColor.opacity(0.4)
                                : Color.accentColor
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.plain)
                .disabled(name.isEmpty || keyword.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: Design.sheetWidth)
        .onAppear {
            name = config.name
            keyword = config.keyword
        }
    }

    @ViewBuilder
    private var currentPhoto: some View {
        if let image = selectedImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else if let nsImage = NSImage(contentsOfFile: config.imagePath) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
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

// MARK: - Reusable Form Field

struct FormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.3)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Design.subtleBorder, lineWidth: 1)
                )
            if let hint = hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Menu Bar Entry Point

// Strong reference to prevent ARC from deallocating the delegate
// (NSApplication.delegate is weak).
private var _menuBarDelegate: MenuBarDelegate?

func runMenuBarMode() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    _menuBarDelegate = MenuBarDelegate()
    app.delegate = _menuBarDelegate
    app.run()
}
