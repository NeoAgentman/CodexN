import AppKit
import CodexNCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ProfileStore()
    private let launcher = Launcher()
    private var statusItem: NSStatusItem?
    private var addProfileWindowController: AddProfileWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "CodexN"
        item.button?.toolTip = "Codex profile launcher"
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "CodexN", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(menuItem("Add Profile...", action: #selector(addProfile)))
        menu.addItem(menuItem("Refresh", action: #selector(refreshMenu)))
        menu.addItem(.separator())

        do {
            let profiles = try store.listProfiles()
            let origin = NSMenuItem(title: "origin (system default)", action: nil, keyEquivalent: "")
            origin.submenu = originMenu()
            menu.addItem(origin)

            if profiles.isEmpty {
                let empty = NSMenuItem(title: "No managed profiles", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
            } else {
                for profile in profiles {
                    let item = NSMenuItem(title: "\(profile.name) (\(profile.id))", action: nil, keyEquivalent: "")
                    item.submenu = profileMenu(profile)
                    menu.addItem(item)
                }
            }
        } catch {
            let item = NSMenuItem(title: "Failed to load profiles", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(menuItem("Open Profiles Folder", action: #selector(openProfilesFolder)))
        menu.addItem(menuItem("Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func profileMenu(_ profile: Profile) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(profileAction("Open Desktop", action: #selector(openDesktop(_:)), profile: profile))
        menu.addItem(profileAction("Open CLI", action: #selector(openCLI(_:)), profile: profile))
        menu.addItem(.separator())
        menu.addItem(profileAction("Backup", action: #selector(backupProfile(_:)), profile: profile))
        menu.addItem(profileAction("Remove...", action: #selector(removeProfile(_:)), profile: profile))
        return menu
    }

    private func originMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem("Open Desktop", action: #selector(openOriginDesktop)))
        menu.addItem(menuItem("Open CLI", action: #selector(openOriginCLI)))
        return menu
    }

    private func menuItem(_ title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func profileAction(_ title: String, action: Selector, profile: Profile) -> NSMenuItem {
        let item = menuItem(title, action: action)
        item.representedObject = profile.id
        return item
    }

    @objc private func refreshMenu() {
        rebuildMenu()
    }

    @objc private func addProfile() {
        if let controller = addProfileWindowController {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = AddProfileWindowController(store: store) { [weak self] in
            self?.rebuildMenu()
        }
        controller.onClose = { [weak self] in
            self?.addProfileWindowController = nil
        }
        addProfileWindowController = controller
        controller.showWindow(nil)
        controller.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openOriginDesktop() {
        do {
            try launcher.openDefaultDesktop()
        } catch {
            showError(error)
        }
    }

    @objc private func openOriginCLI() {
        do {
            try launcher.openDefaultCLIInTerminal()
        } catch {
            showError(error)
        }
    }

    @objc private func openDesktop(_ sender: NSMenuItem) {
        withProfile(sender) { profile in
            try launcher.openDesktop(profile: profile)
        }
    }

    @objc private func openCLI(_ sender: NSMenuItem) {
        withProfile(sender) { profile in
            try launcher.openCLIInTerminal(profile: profile)
        }
    }

    @objc private func backupProfile(_ sender: NSMenuItem) {
        withProfile(sender) { profile in
            let backup = try store.backupProfile(id: profile.id)
            showMessage(title: "Backup Created", message: backup.path)
        }
    }

    @objc private func removeProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        guard confirm(title: "Remove Profile", message: "Remove \(id) from CodexN? Files remain on disk. No backup is created automatically.") else {
            return
        }
        do {
            _ = try store.deleteProfile(id: id)
            rebuildMenu()
        } catch {
            showError(error)
        }
    }

    @objc private func openProfilesFolder() {
        NSWorkspace.shared.open(store.root)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func withProfile(_ sender: NSMenuItem, action: (Profile) throws -> Void) {
        guard let id = sender.representedObject as? String else { return }
        do {
            try action(try store.getProfile(id: id))
        } catch {
            showError(error)
        }
    }

    private func confirm(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showError(_ error: Error) {
        showMessage(title: "CodexN Error", message: String(describing: error), style: .critical)
    }

    private func showMessage(title: String, message: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

@MainActor
final class AddProfileWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let store: ProfileStore
    private let onComplete: () -> Void
    private let idField = NSTextField(string: "work")
    private let nameField = NSTextField(string: "Work")
    private let modePopup = NSPopUpButton()
    private let authMode = NSSegmentedControl(labels: ["OAuth login", "Custom API key"], trackingMode: .selectOne, target: nil, action: nil)
    private let authModeStack = NSStackView()
    private let apiFieldsStack = NSStackView()
    private let providerField = NSTextField(string: "")
    private let modelField = NSTextField(string: "")
    private let baseURLField = NSTextField(string: "")
    private let apiKeyField = NSSecureTextField(string: "")

    init(store: ProfileStore, onComplete: @escaping () -> Void) {
        self.store = store
        self.onComplete = onComplete

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Add Profile"
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
        updateVisibility()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private func buildContent(in window: NSWindow) {
        modePopup.addItems(withTitles: ["Import from default", "New profile"])
        modePopup.target = self
        modePopup.action = #selector(modeChanged)

        authMode.selectedSegment = 0
        authMode.target = self
        authMode.action = #selector(authModeChanged)

        providerField.placeholderString = "zl"
        modelField.placeholderString = "gpt-5.5"
        baseURLField.placeholderString = "https://api.example.com/v1"
        apiKeyField.placeholderString = "API key"

        authModeStack.orientation = .vertical
        authModeStack.spacing = 6
        authModeStack.addArrangedSubview(fieldLabel("New profile auth"))
        authModeStack.addArrangedSubview(authMode)

        apiFieldsStack.orientation = .vertical
        apiFieldsStack.spacing = 8
        apiFieldsStack.addArrangedSubview(fieldLabel("Model Provider"))
        apiFieldsStack.addArrangedSubview(providerField)
        apiFieldsStack.addArrangedSubview(fieldLabel("Model Name"))
        apiFieldsStack.addArrangedSubview(modelField)
        apiFieldsStack.addArrangedSubview(fieldLabel("Base URL"))
        apiFieldsStack.addArrangedSubview(baseURLField)
        apiFieldsStack.addArrangedSubview(fieldLabel("API Key"))
        apiFieldsStack.addArrangedSubview(apiKeyField)

        let createButton = NSButton(title: "Create", target: self, action: #selector(createProfile))
        createButton.bezelStyle = .rounded
        createButton.keyEquivalent = "\r"

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let buttonStack = NSStackView(views: [cancelButton, createButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8

        let spacer = NSView()
        let buttonRow = NSStackView(views: [spacer, buttonStack])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY

        let root = NSStackView(views: [
            fieldLabel("Profile ID"),
            idField,
            fieldLabel("Display Name"),
            nameField,
            fieldLabel("Mode"),
            modePopup,
            authModeStack,
            apiFieldsStack,
            buttonRow
        ])
        root.orientation = .vertical
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(root)
        window.contentView = content

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
            idField.heightAnchor.constraint(equalToConstant: 24),
            nameField.heightAnchor.constraint(equalToConstant: 24),
            providerField.heightAnchor.constraint(equalToConstant: 24),
            modelField.heightAnchor.constraint(equalToConstant: 24),
            baseURLField.heightAnchor.constraint(equalToConstant: 24),
            apiKeyField.heightAnchor.constraint(equalToConstant: 24),
            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 1)
        ])
    }

    @objc private func modeChanged() {
        let importMode = modePopup.indexOfSelectedItem == 0
        if importMode && (idField.stringValue.isEmpty || idField.stringValue == "work") {
            idField.stringValue = "default"
            nameField.stringValue = "Default"
        } else if !importMode && (idField.stringValue.isEmpty || idField.stringValue == "default") {
            idField.stringValue = "work"
            nameField.stringValue = "Work"
        }
        updateVisibility()
    }

    @objc private func authModeChanged() {
        updateVisibility()
    }

    @objc private func cancel() {
        close()
    }

    @objc private func createProfile() {
        do {
            let id = trimmed(idField.stringValue)
            let name = trimmed(nameField.stringValue)
            let displayName = name.isEmpty ? id : name

            if modePopup.indexOfSelectedItem == 0 {
                _ = try store.importDefaultProfile(id: id, name: displayName)
            } else if authMode.selectedSegment == 0 {
                _ = try store.createProfile(id: id, name: displayName)
            } else {
                _ = try store.createAPIKeyProfile(
                    id: id,
                    name: displayName,
                    provider: trimmed(providerField.stringValue),
                    model: trimmed(modelField.stringValue),
                    baseURL: trimmed(baseURLField.stringValue),
                    apiKey: apiKeyField.stringValue
                )
            }

            onComplete()
            close()
        } catch {
            showError(error)
        }
    }

    private func updateVisibility() {
        let isNewProfile = modePopup.indexOfSelectedItem == 1
        let isAPIKey = isNewProfile && authMode.selectedSegment == 1
        authModeStack.isHidden = !isNewProfile
        apiFieldsStack.isHidden = !isAPIKey
    }

    private func fieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        return label
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "CodexN Error"
        alert.informativeText = String(describing: error)
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window!)
    }
}

private func trimmed(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
