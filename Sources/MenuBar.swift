// MenuBar.swift — termavatar
// Menu bar UI: NSStatusItem + NSPopover with SwiftUI views.

import AppKit
import SwiftUI
import ServiceManagement

// MARK: - Design Tokens

private enum DS {
    static let popW: CGFloat = 360
    static let popH: CGFloat = 460
    static let sheetW: CGFloat = 340
    static let avatarGrid: CGFloat = 60
    static let avatarLarge: CGFloat = 72
    static let cardRadius: CGFloat = 12
    static let green = Color(nsColor: NSColor(red: 0.30, green: 0.78, blue: 0.47, alpha: 1.0))
    static let red = Color(nsColor: NSColor(red: 0.92, green: 0.34, blue: 0.34, alpha: 1.0))
    static let cardBg = Color.primary.opacity(0.04)
    static let cardHover = Color.primary.opacity(0.08)
    static let border = Color.primary.opacity(0.06)
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

private struct EditTarget: Identifiable {
    let id: String
    init(_ keyword: String) { self.id = keyword }
}

struct MenuBarView: View {
    let watcher: AvatarWatcher
    @State private var configs: [String: AvatarConfig] = [:]
    @State private var showingAddSheet = false
    @State private var editTarget: EditTarget? = nil
    @State private var startAtLogin: Bool = (SMAppService.mainApp.status == .enabled)

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            if configs.isEmpty {
                emptyState
            } else {
                avatarGrid
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
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Termavatar")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("Your terminal crew")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { showingAddSheet = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(Circle())
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.06))
                    .frame(width: 90, height: 90)
                Circle()
                    .fill(Color.accentColor.opacity(0.04))
                    .frame(width: 70, height: 70)
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor.opacity(0.5))
            }
            VStack(spacing: 6) {
                Text("No avatars yet")
                    .font(.system(size: 15, weight: .semibold))
                Text("Add avatars to identify your terminal windows")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: { showingAddSheet = true }) {
                Label("Add Your First Avatar", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    // MARK: Avatar Grid

    private var avatarGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(configs.keys.sorted(), id: \.self) { keyword in
                    if let config = configs[keyword] {
                        AvatarCard(
                            config: config,
                            onEdit: { editTarget = EditTarget(keyword) },
                            onRemove: {
                                AvatarConfig.remove(keyword: keyword)
                                reload()
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 0) {
            // Status
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(DS.green.opacity(0.2))
                        .frame(width: 14, height: 14)
                    Circle()
                        .fill(DS.green)
                        .frame(width: 8, height: 8)
                }
                Text("\(configs.count) active")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Login toggle
            Toggle(isOn: $startAtLogin) {
                Text("Auto-start")
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

            Spacer().frame(width: 12)

            // Quit
            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(DS.cardBg)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DS.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Quit Termavatar")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(DS.cardBg)
    }

    private func reload() {
        configs = AvatarConfig.loadAll()
        watcher.poll()
    }
}

// MARK: - Avatar Card (Grid Cell)

struct AvatarCard: View {
    let config: AvatarConfig
    let onEdit: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            // Avatar photo with active dot
            ZStack(alignment: .topTrailing) {
                avatarImage
                    .frame(width: DS.avatarGrid, height: DS.avatarGrid)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(hovering ? 0.18 : 0.08), radius: hovering ? 6 : 3, y: hovering ? 3 : 1)

                // Active indicator
                Circle()
                    .fill(DS.green)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                    .offset(x: 2, y: -1)
            }

            // Name
            Text(config.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: DS.cardRadius)
                .fill(hovering ? DS.cardHover : DS.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.cardRadius)
                .stroke(hovering ? Color.accentColor.opacity(0.3) : DS.border, lineWidth: 1)
        )
        .scaleEffect(hovering ? 1.03 : 1.0)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onEdit() }
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive, action: onRemove) {
                Label("Delete", systemImage: "trash")
            }
        }
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
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.10)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Text(String(config.name.prefix(1)).uppercased())
                        .font(.system(size: 22, weight: .bold, design: .rounded))
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
            VStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accentColor)
                Text("New Avatar")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("Add a floating avatar to your terminal")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 26)
            .padding(.bottom, 22)

            photoSection
                .padding(.bottom, 22)

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
                    hint: "Avatar shows when terminal title contains this"
                )
            }
            .padding(.horizontal, 26)

            if let error = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(error)
                        .font(.system(size: 11))
                }
                .foregroundColor(DS.red)
                .padding(.top, 12)
            }

            Spacer().frame(height: 22)

            sheetButtons(
                cancelAction: { isPresented = false },
                confirmLabel: "Add Avatar",
                confirmAction: addAvatar,
                confirmDisabled: name.isEmpty || keyword.isEmpty || selectedImagePath == nil
            )
            .padding(.horizontal, 26)
            .padding(.bottom, 26)
        }
        .frame(width: DS.sheetW)
    }

    private var photoSection: some View {
        VStack(spacing: 10) {
            ZStack {
                if let image = selectedImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: DS.avatarLarge, height: DS.avatarLarge)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                } else {
                    Circle()
                        .fill(DS.cardBg)
                        .frame(width: DS.avatarLarge, height: DS.avatarLarge)
                        .overlay(
                            Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                .foregroundStyle(Color.primary.opacity(0.12))
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
            VStack(spacing: 12) {
                ZStack {
                    currentPhoto
                        .frame(width: DS.avatarLarge, height: DS.avatarLarge)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        )
                        .offset(x: 24, y: 24)
                        .onTapGesture { pickImage() }
                }

                Text("Edit Avatar")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .padding(.top, 26)
            .padding(.bottom, 22)

            VStack(spacing: 14) {
                FormField(label: "Name", placeholder: "Display name", text: $name)
                FormField(label: "Match Keyword", placeholder: "Text in terminal title", text: $keyword)
            }
            .padding(.horizontal, 26)

            Spacer().frame(height: 22)

            sheetButtons(
                cancelAction: { isPresented = false },
                confirmLabel: "Save Changes",
                confirmAction: save,
                confirmDisabled: name.isEmpty || keyword.isEmpty
            )
            .padding(.horizontal, 26)
            .padding(.bottom, 26)
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

struct FormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DS.cardBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DS.border, lineWidth: 1)
                )
            if let hint = hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private func sheetButtons(
    cancelAction: @escaping () -> Void,
    confirmLabel: String,
    confirmAction: @escaping () -> Void,
    confirmDisabled: Bool
) -> some View {
    HStack(spacing: 10) {
        Button(action: cancelAction) {
            Text("Cancel")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(DS.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(DS.border, lineWidth: 1))
        }
        .keyboardShortcut(.cancelAction)
        .buttonStyle(.plain)

        Button(action: confirmAction) {
            Text(confirmLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(confirmDisabled ? Color.accentColor.opacity(0.4) : Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: Color.accentColor.opacity(confirmDisabled ? 0 : 0.25), radius: 3, y: 1)
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.plain)
        .disabled(confirmDisabled)
    }
}

// MARK: - Menu Bar Entry Point

private var _menuBarDelegate: MenuBarDelegate?

func runMenuBarMode() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    _menuBarDelegate = MenuBarDelegate()
    app.delegate = _menuBarDelegate
    app.run()
}
