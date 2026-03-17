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

        // Status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "Termavatar")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Popover with SwiftUI content
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(watcher: watcher)
        )

        // Start watcher
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

// MARK: - SwiftUI Views

struct MenuBarView: View {
    let watcher: AvatarWatcher
    @State private var configs: [String: AvatarConfig] = [:]
    @State private var showingAddSheet = false
    @State private var startAtLogin: Bool = (SMAppService.mainApp.status == .enabled)

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "person.crop.circle")
                    .font(.title2)
                Text("Termavatar")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Avatar list
            if configs.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No avatars yet")
                        .foregroundColor(.secondary)
                    Text("Click + to add your first avatar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(configs.keys.sorted(), id: \.self) { keyword in
                            if let config = configs[keyword] {
                                AvatarRow(config: config, onRemove: {
                                    AvatarConfig.remove(keyword: keyword)
                                    reload()
                                })
                            }
                        }
                    }
                }
            }

            Divider()

            // Footer
            VStack(spacing: 6) {
                Toggle("Start at Login", isOn: $startAtLogin)
                    .toggleStyle(.switch)
                    .font(.caption)
                    .onChange(of: startAtLogin) { _, newValue in
                        if newValue {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                        // Sync state back in case register/unregister failed
                        startAtLogin = (SMAppService.mainApp.status == .enabled)
                    }

                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Watching \(configs.count) avatar\(configs.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Quit") {
                        NSApp.terminate(nil)
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 320, height: 400)
        .onAppear { reload() }
        .sheet(isPresented: $showingAddSheet) {
            AddAvatarSheet(isPresented: $showingAddSheet, onAdd: { reload() })
        }
    }

    private func reload() {
        configs = AvatarConfig.loadAll()
        watcher.poll()
    }
}

struct AvatarRow: View {
    let config: AvatarConfig
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Avatar thumbnail
            if let nsImage = NSImage(contentsOfFile: config.imagePath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.system(size: 13, weight: .medium))
                Text("keyword: \(config.keyword) · \(config.corner) · \(config.size)px")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.7))
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct AddAvatarSheet: View {
    @Binding var isPresented: Bool
    let onAdd: () -> Void

    @State private var name = ""
    @State private var keyword = ""
    @State private var corner = "br"
    @State private var size = "90"
    @State private var selectedImagePath: String?
    @State private var selectedImage: NSImage?
    @State private var errorMessage: String?

    let corners = ["br", "bl", "tr", "tl"]

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Avatar")
                .font(.headline)

            // Photo picker
            HStack {
                if let image = selectedImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5]))
                        .foregroundColor(.secondary)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "photo.badge.plus")
                                .foregroundColor(.secondary)
                        )
                }

                Button("Choose Photo...") {
                    pickImage()
                }
            }

            // Fields
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Name:")
                        .frame(width: 60, alignment: .trailing)
                    TextField("Display name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: name) { _, newValue in
                            if keyword.isEmpty || keyword == name.replacingOccurrences(of: " ", with: "") {
                                keyword = newValue
                            }
                        }
                }

                HStack {
                    Text("Keyword:")
                        .frame(width: 60, alignment: .trailing)
                    TextField("Window title match", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Corner:")
                        .frame(width: 60, alignment: .trailing)
                    Picker("", selection: $corner) {
                        ForEach(corners, id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                HStack {
                    Text("Size:")
                        .frame(width: 60, alignment: .trailing)
                    TextField("90", text: $size)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("px")
                        .foregroundColor(.secondary)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            // Actions
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    addAvatar()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || keyword.isEmpty || selectedImagePath == nil)
            }
        }
        .padding(20)
        .frame(width: 340)
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

        // Crop to circle and save
        guard let savedPath = AvatarConfig.cropCircle(sourcePath: sourcePath, name: name) else {
            errorMessage = "Failed to process image"
            return
        }

        let avatarSize = Int(size) ?? 90
        let config = AvatarConfig(
            keyword: keyword, name: name, imagePath: savedPath,
            corner: corner, size: avatarSize
        )
        AvatarConfig.add(config)
        onAdd()
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
