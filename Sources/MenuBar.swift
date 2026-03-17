// MenuBar.swift — termavatar
// Menu bar UI: NSStatusItem + NSPopover with SwiftUI views.

import AppKit
import SwiftUI
import ServiceManagement

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
        popover.contentSize = NSSize(width: 300, height: 420)
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
    @State private var editingKeyword: String? = nil
    @State private var startAtLogin: Bool = (SMAppService.mainApp.status == .enabled)

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Termavatar")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Avatar list
            if configs.isEmpty {
                emptyState
            } else {
                avatarList
            }

            Divider()
                .padding(.horizontal, 12)

            // Footer
            footer
        }
        .frame(width: 300, height: 420)
        .onAppear { reload() }
        .sheet(isPresented: $showingAddSheet) {
            AddAvatarSheet(isPresented: $showingAddSheet, onAdd: { reload() })
        }
        .sheet(item: $editingKeyword) { keyword in
            if let config = configs[keyword] {
                EditAvatarSheet(
                    config: config,
                    isPresented: Binding(
                        get: { editingKeyword != nil },
                        set: { if !$0 { editingKeyword = nil } }
                    ),
                    onSave: { reload() }
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No avatars")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Add an avatar to get started")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var avatarList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(configs.keys.sorted(), id: \.self) { keyword in
                    if let config = configs[keyword] {
                        AvatarRow(
                            config: config,
                            onEdit: { editingKeyword = keyword },
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

    private var footer: some View {
        VStack(spacing: 8) {
            Toggle("Start at Login", isOn: $startAtLogin)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 12))
                .onChange(of: startAtLogin) { _, newValue in
                    if newValue {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                    startAtLogin = (SMAppService.mainApp.status == .enabled)
                }

            HStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("\(configs.count) avatar\(configs.count == 1 ? "" : "s") active")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func reload() {
        configs = AvatarConfig.loadAll()
        watcher.poll()
    }
}

// Make String work with .sheet(item:)
extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - Avatar Row

struct AvatarRow: View {
    let config: AvatarConfig
    let onEdit: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            avatarImage
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)

            // Name and keyword
            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if config.keyword != config.name {
                    Text(config.keyword)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Actions (visible on hover)
            if hovering {
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(hovering ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let nsImage = NSImage(contentsOfFile: config.imagePath) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
        } else {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .overlay(
                    Text(String(config.name.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
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

    var body: some View {
        VStack(spacing: 20) {
            Text("New Avatar")
                .font(.system(size: 15, weight: .semibold))

            // Photo
            photoSection

            // Name
            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("e.g. Jack", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: name) { _, newValue in
                        if keyword.isEmpty || keyword == previousName {
                            keyword = newValue
                        }
                        previousName = newValue
                    }
            }

            // Keyword
            VStack(alignment: .leading, spacing: 6) {
                Text("Window Title Keyword")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Text to match in terminal title", text: $keyword)
                    .textFieldStyle(.roundedBorder)
                Text("The avatar appears when a terminal title contains this text")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.system(size: 11))
            }

            // Actions
            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Avatar") { addAvatar() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || keyword.isEmpty || selectedImagePath == nil)
            }
        }
        .padding(24)
        .frame(width: 320)
    }

    @State private var previousName = ""

    private var photoSection: some View {
        HStack(spacing: 16) {
            if let image = selectedImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            } else {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle(.quaternary)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.tertiary)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Button("Choose Photo...") { pickImage() }
                    .controlSize(.small)
                Text("Square photos work best")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
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
        VStack(spacing: 20) {
            Text("Edit Avatar")
                .font(.system(size: 15, weight: .semibold))

            // Current photo
            HStack(spacing: 16) {
                if let image = selectedImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                } else if let nsImage = NSImage(contentsOfFile: config.imagePath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Button("Change Photo...") { pickImage() }
                        .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Display name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Window Title Keyword")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Keyword", text: $keyword)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || keyword.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320)
        .onAppear {
            name = config.name
            keyword = config.keyword
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
        // Remove old entry
        AvatarConfig.remove(keyword: config.keyword)

        // Process new image if changed
        var imagePath = config.imagePath
        if let newPath = selectedImagePath {
            if let cropped = AvatarConfig.cropCircle(sourcePath: newPath, name: name) {
                imagePath = cropped
            }
        } else if name != config.name {
            // Rename image file if name changed
            let newPath = (AvatarConfig.avatarsDir as NSString).appendingPathComponent("\(name).png")
            try? FileManager.default.moveItem(atPath: config.imagePath, toPath: newPath)
            imagePath = newPath
        }

        let updated = AvatarConfig(
            keyword: keyword, name: name, imagePath: imagePath,
            corner: config.corner, size: config.size
        )
        AvatarConfig.add(updated)

        // Sync rename to live agent-avatar config
        AvatarConfig.syncRenameToLiveConfig(
            oldKeyword: config.keyword,
            newKeyword: keyword,
            newName: name
        )

        onSave()
        isPresented = false
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
