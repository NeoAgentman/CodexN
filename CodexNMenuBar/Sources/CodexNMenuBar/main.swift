import AppKit
import CodexNCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ProfileStore()
    private let launcher = Launcher()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var panelController: ProfilePanelViewController?
    private var addProfileWindowController: AddProfileWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "CodexN"
        item.button?.toolTip = "Codex profile launcher"
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        statusItem = item
        preparePopover()
    }

    private func preparePopover() {
        let controller = ProfilePanelViewController(
            store: store,
            launcher: launcher,
            onAddProfile: { [weak self] in self?.addProfile() },
            onOpenProfilesFolder: { [weak self] in self?.openProfilesFolder() },
            onQuit: { [weak self] in self?.quit() },
            onError: { [weak self] error in self?.showError(error) },
            onMessage: { [weak self] title, message in self?.showMessage(title: title, message: message) }
        )
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 560)
        popover.contentViewController = controller
        panelController = controller
        self.popover = popover
    }

    @objc private func togglePanel() {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            panelController?.reloadProfiles()
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover?.contentViewController?.view.window?.makeKey()
        }
    }

    private func addProfile() {
        if let controller = addProfileWindowController {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = AddProfileWindowController(store: store) { [weak self] in
            self?.panelController?.reloadProfiles()
        }
        controller.onClose = { [weak self] in
            self?.addProfileWindowController = nil
        }
        addProfileWindowController = controller
        controller.showWindow(nil)
        controller.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openProfilesFolder() {
        NSWorkspace.shared.open(store.root)
    }

    private func quit() {
        NSApp.terminate(nil)
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
final class ProfilePanelViewController: NSViewController {
    private let store: ProfileStore
    private let launcher: Launcher
    private let onAddProfile: () -> Void
    private let onOpenProfilesFolder: () -> Void
    private let onQuit: () -> Void
    private let onError: (Error) -> Void
    private let onMessage: (String, String) -> Void
    private let headerCountLabel = NSTextField(labelWithString: "")
    private let profileStack = NSStackView()
    private let scrollView = NSScrollView()

    init(
        store: ProfileStore,
        launcher: Launcher,
        onAddProfile: @escaping () -> Void,
        onOpenProfilesFolder: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        onError: @escaping (Error) -> Void,
        onMessage: @escaping (String, String) -> Void
    ) {
        self.store = store
        self.launcher = launcher
        self.onAddProfile = onAddProfile
        self.onOpenProfilesFolder = onOpenProfilesFolder
        self.onQuit = onQuit
        self.onError = onError
        self.onMessage = onMessage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSVisualEffectView()
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        root.translatesAutoresizingMaskIntoConstraints = false

        let header = makeHeader()
        let footer = makeFooter()

        profileStack.orientation = .vertical
        profileStack.alignment = .leading
        profileStack.spacing = 10
        profileStack.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(profileStack)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = documentView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(header)
        root.addSubview(scrollView)
        root.addSubview(footer)
        view = root

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),

            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),

            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            profileStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            profileStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            profileStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            profileStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadProfiles()
    }

    func reloadProfiles() {
        guard isViewLoaded else { return }
        profileStack.arrangedSubviews.forEach { view in
            profileStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        do {
            let profiles = try store.listProfiles()
            headerCountLabel.stringValue = "\(profiles.count) managed"
            profileStack.addArrangedSubview(makeOriginCard())
            if profiles.isEmpty {
                profileStack.addArrangedSubview(makeEmptyState())
            } else {
                profiles.forEach { profile in
                    profileStack.addArrangedSubview(makeProfileCard(profile))
                }
            }
        } catch {
            headerCountLabel.stringValue = "Unavailable"
            profileStack.addArrangedSubview(makeErrorState(error))
        }
    }

    private func makeHeader() -> NSView {
        let title = NSTextField(labelWithString: "CodexN")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: "Isolated Codex profiles")
        subtitle.font = .systemFont(ofSize: 12, weight: .medium)
        subtitle.textColor = .secondaryLabelColor

        headerCountLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        headerCountLabel.textColor = NSColor(calibratedRed: 0.20, green: 0.38, blue: 0.92, alpha: 1)
        headerCountLabel.alignment = .center
        headerCountLabel.wantsLayer = true
        headerCountLabel.layer?.cornerRadius = 10
        headerCountLabel.layer?.backgroundColor = NSColor(calibratedRed: 0.20, green: 0.38, blue: 0.92, alpha: 0.12).cgColor

        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical
        titleStack.spacing = 1

        let addButton = iconButton(symbol: "plus", accessibility: "Add Profile", action: #selector(addProfile))
        let refreshButton = iconButton(symbol: "arrow.clockwise", accessibility: "Refresh", action: #selector(refresh))
        let actions = NSStackView(views: [headerCountLabel, refreshButton, addButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8

        let header = NSStackView(views: [titleStack, NSView(), actions])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            headerCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 84),
            headerCountLabel.heightAnchor.constraint(equalToConstant: 22)
        ])
        return header
    }

    private func makeFooter() -> NSView {
        let folder = footerButton("Profiles Folder", action: #selector(openProfilesFolder))
        let quit = footerButton("Quit", action: #selector(quit))
        let footer = NSStackView(views: [folder, NSView(), quit])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.translatesAutoresizingMaskIntoConstraints = false
        return footer
    }

    private func makeOriginCard() -> NSView {
        profileCard(
            title: "origin",
            subtitle: "system default Codex",
            badge: "DEFAULT",
            accent: NSColor(calibratedRed: 0.15, green: 0.64, blue: 0.45, alpha: 1),
            primaryActions: [
                ("Desktop", #selector(openOriginDesktop)),
                ("CLI", #selector(openOriginCLI))
            ],
            secondaryActions: []
        )
    }

    private func makeProfileCard(_ profile: Profile) -> NSView {
        let badge = profile.apiKeyEnvName == nil ? "OAUTH" : "API KEY"
        let subtitle = "\(profile.id) · \(profile.defaultProvider)"
        return profileCard(
            title: profile.name,
            subtitle: subtitle,
            badge: badge,
            accent: NSColor(calibratedRed: 0.23, green: 0.42, blue: 0.95, alpha: 1),
            primaryActions: [
                ("Desktop", #selector(openDesktop(_:))),
                ("CLI", #selector(openCLI(_:)))
            ],
            secondaryActions: [
                ("Backup", #selector(backupProfile(_:))),
                ("Remove", #selector(removeProfile(_:)))
            ],
            profileID: profile.id
        )
    }

    private func profileCard(
        title: String,
        subtitle: String,
        badge: String,
        accent: NSColor,
        primaryActions: [(String, Selector)],
        secondaryActions: [(String, Selector)],
        profileID: String? = nil
    ) -> NSView {
        let card = RoundedPanelView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.accentColor = accent

        let mark = NSTextField(labelWithString: String(title.prefix(1)).uppercased())
        mark.font = .systemFont(ofSize: 17, weight: .bold)
        mark.alignment = .center
        mark.textColor = .white
        mark.wantsLayer = true
        mark.layer?.cornerRadius = 10
        mark.layer?.backgroundColor = accent.cgColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingMiddle

        let badgeLabel = NSTextField(labelWithString: badge)
        badgeLabel.font = .monospacedSystemFont(ofSize: 9, weight: .bold)
        badgeLabel.textColor = accent
        badgeLabel.alignment = .center
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.cornerRadius = 8
        badgeLabel.layer?.backgroundColor = accent.withAlphaComponent(0.12).cgColor

        let labels = NSStackView(views: [titleLabel, subtitleLabel])
        labels.orientation = .vertical
        labels.spacing = 1

        let heading = NSStackView(views: [mark, labels, NSView(), badgeLabel])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 10

        let primaryButtons = primaryActions.map { title, selector in
            cardButton(title, action: selector, profileID: profileID, emphasized: title == "Desktop")
        }
        let secondaryButtons = secondaryActions.map { title, selector in
            cardButton(title, action: selector, profileID: profileID, emphasized: false)
        }
        let actionRow = NSStackView(views: primaryButtons + [NSView()] + secondaryButtons)
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 7

        let content = NSStackView(views: [heading, actionRow])
        content.orientation = .vertical
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalTo: profileStack.widthAnchor),
            mark.widthAnchor.constraint(equalToConstant: 38),
            mark.heightAnchor.constraint(equalToConstant: 38),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 58),
            badgeLabel.heightAnchor.constraint(equalToConstant: 18),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 13),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -13),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
        return card
    }

    private func makeEmptyState() -> NSView {
        let label = NSTextField(labelWithString: "No managed profiles yet")
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        let message = NSTextField(labelWithString: "Create an isolated OAuth or API key profile to get started.")
        message.font = .systemFont(ofSize: 12)
        message.textColor = .secondaryLabelColor
        message.alignment = .center
        let add = pillButton("Add Profile", action: #selector(addProfile), emphasized: true)

        let stack = NSStackView(views: [label, message, add])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let panel = RoundedPanelView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)
        NSLayoutConstraint.activate([
            panel.widthAnchor.constraint(equalTo: profileStack.widthAnchor),
            stack.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -22),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: panel.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: panel.trailingAnchor, constant: -18)
        ])
        return panel
    }

    private func makeErrorState(_ error: Error) -> NSView {
        let label = NSTextField(labelWithString: "Failed to load profiles")
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        let message = NSTextField(wrappingLabelWithString: String(describing: error))
        message.font = .systemFont(ofSize: 12)
        message.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [label, message])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let panel = RoundedPanelView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)
        NSLayoutConstraint.activate([
            panel.widthAnchor.constraint(equalTo: profileStack.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -16)
        ])
        return panel
    }

    private func cardButton(_ title: String, action: Selector, profileID: String?, emphasized: Bool) -> NSButton {
        let button = pillButton(title, action: action, emphasized: emphasized)
        if let profileID {
            button.identifier = NSUserInterfaceItemIdentifier(profileID)
        }
        return button
    }

    private func pillButton(_ title: String, action: Selector, emphasized: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = emphasized ? .rounded : .inline
        button.controlSize = .small
        button.font = .systemFont(ofSize: 12, weight: emphasized ? .semibold : .medium)
        return button
    }

    private func footerButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .inline
        button.font = .systemFont(ofSize: 12, weight: .medium)
        return button
    }

    private func iconButton(symbol: String, accessibility: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: accessibility) ?? NSImage(), target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.toolTip = accessibility
        return button
    }

    @objc private func refresh() {
        reloadProfiles()
    }

    @objc private func addProfile() {
        onAddProfile()
    }

    @objc private func openProfilesFolder() {
        onOpenProfilesFolder()
    }

    @objc private func quit() {
        onQuit()
    }

    @objc private func openOriginDesktop() {
        perform { try launcher.openDefaultDesktop() }
    }

    @objc private func openOriginCLI() {
        perform { try launcher.openDefaultCLIInTerminal() }
    }

    @objc private func openDesktop(_ sender: NSButton) {
        withProfile(sender) { try launcher.openDesktop(profile: $0) }
    }

    @objc private func openCLI(_ sender: NSButton) {
        withProfile(sender) { try launcher.openCLIInTerminal(profile: $0) }
    }

    @objc private func backupProfile(_ sender: NSButton) {
        withProfile(sender) { profile in
            let backup = try store.backupProfile(id: profile.id)
            onMessage("Backup Created", backup.path)
        }
    }

    @objc private func removeProfile(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        guard confirm(title: "Remove Profile", message: "Remove \(id) from CodexN? Files remain on disk. No backup is created automatically.") else {
            return
        }
        perform {
            _ = try store.deleteProfile(id: id)
            reloadProfiles()
        }
    }

    private func withProfile(_ sender: NSButton, action: (Profile) throws -> Void) {
        guard let id = sender.identifier?.rawValue else { return }
        perform {
            try action(try store.getProfile(id: id))
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            onError(error)
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
}

@MainActor
final class RoundedPanelView: NSView {
    var accentColor: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSColor.controlBackgroundColor.withAlphaComponent(0.62).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.42).setStroke()
        path.lineWidth = 1
        path.stroke()

        let accentPath = NSBezierPath(
            roundedRect: NSRect(x: bounds.minX, y: bounds.minY, width: 4, height: bounds.height),
            xRadius: 2,
            yRadius: 2
        )
        accentColor.withAlphaComponent(0.92).setFill()
        accentPath.fill()
    }
}

@MainActor
final class AddProfileWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let store: ProfileStore
    private let onComplete: () -> Void
    private let formWidth: CGFloat = 402
    private let labelWidth: CGFloat = 90
    private let controlWidth: CGFloat = 300
    private let idField = NSTextField(string: "")
    private let nameField = NSTextField(string: "")
    private let modePopup = NSPopUpButton()
    private let authMode = NSSegmentedControl(labels: ["OAuth login", "Custom API key"], trackingMode: .selectOne, target: nil, action: nil)
    private var authModeRow: NSView?
    private var apiFieldRows: [NSView] = []
    private let providerField = NSTextField(string: "")
    private let modelField = NSTextField(string: "")
    private let baseURLField = NSTextField(string: "")
    private let apiKeyField = NSSecureTextField(string: "")

    init(store: ProfileStore, onComplete: @escaping () -> Void) {
        self.store = store
        self.onComplete = onComplete

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 380),
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
        modePopup.selectItem(withTitle: "New profile")

        authMode.selectedSegment = 0
        authMode.target = self
        authMode.action = #selector(authModeChanged)

        [idField, nameField, providerField, modelField, baseURLField, apiKeyField].forEach { field in
            field.lineBreakMode = .byTruncatingTail
            field.controlSize = .regular
        }

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

        let authModeRow = formRow(label: "New profile auth", control: authMode)
        let providerRow = formRow(label: "Model Provider", control: providerField)
        let modelRow = formRow(label: "Model Name", control: modelField)
        let baseURLRow = formRow(label: "Base URL", control: baseURLField)
        let apiKeyRow = formRow(label: "API Key", control: apiKeyField)
        self.authModeRow = authModeRow
        apiFieldRows = [providerRow, modelRow, baseURLRow, apiKeyRow]

        let root = NSStackView(views: [
            formRow(label: "Profile ID", control: idField),
            formRow(label: "Display Name", control: nameField),
            formRow(label: "Mode", control: modePopup),
            authModeRow,
            providerRow,
            modelRow,
            baseURLRow,
            apiKeyRow,
            buttonRow
        ])
        root.orientation = .vertical
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(root)
        window.contentView = content

        NSLayoutConstraint.activate([
            root.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            root.widthAnchor.constraint(equalToConstant: formWidth),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 1)
        ])
    }

    @objc private func modeChanged() {
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
        authModeRow?.isHidden = !isNewProfile
        apiFieldRows.forEach { $0.isHidden = !isAPIKey }
    }

    private func formRow(label text: String, control: NSView) -> NSStackView {
        let label = fieldLabel(text)
        control.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: labelWidth),
            control.widthAnchor.constraint(equalToConstant: controlWidth)
        ])

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func fieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
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
