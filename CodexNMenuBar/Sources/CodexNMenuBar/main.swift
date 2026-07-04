import AppKit
import CodexNCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ProfileStore()
    private let launcher = Launcher()
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "CodexN"
        item.button?.toolTip = "Codex profile launcher"
        statusItem = item

        let menu = NSMenu()
        menu.delegate = self
        statusMenu = menu
        statusItem?.menu = menu
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let menu = statusMenu else { return }
        menu.removeAllItems()

        let profiles: [Profile]
        let loadError: String?
        do {
            profiles = try store.listProfiles()
            loadError = nil
        } catch {
            profiles = []
            loadError = String(describing: error)
        }

        let header = ProfileMenuHeader()
        let hosting = MenuHostingView(rootView: header)
        let width: CGFloat = 280
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 1)
        let height = max(1, ceil(hosting.fittingSize.height))
        hosting.applyMeasuredSize(width: width, height: height)

        let headerItem = NSMenuItem()
        headerItem.view = hosting
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        let defaultCodex = NSMenuItem(title: "Default Codex", action: nil, keyEquivalent: "")
        defaultCodex.image = NSImage(systemSymbolName: "house", accessibilityDescription: "Default Codex")
        defaultCodex.submenu = defaultCodexMenu()
        menu.addItem(defaultCodex)

        if let loadError {
            let errorItem = NSMenuItem(title: "Failed to load profiles", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            errorItem.toolTip = loadError
            menu.addItem(errorItem)
        } else {
            profiles.forEach { profile in
                let item = NSMenuItem(title: profileMenuTitle(profile), action: nil, keyEquivalent: "")
                item.image = NSImage(
                    systemSymbolName: profile.apiKeyEnvName == nil ? "person.crop.circle" : "key",
                    accessibilityDescription: profile.name
                )
                item.submenu = profileMenu(profile)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(menuItem("Settings...", symbol: "gearshape", action: #selector(settingsFromMenu)))
        menu.addItem(menuItem("Open Profiles Folder", symbol: "folder", action: #selector(openProfilesFolderFromMenu)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit", symbol: "xmark.rectangle", action: #selector(quitFromMenu)))
    }

    private func defaultCodexMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem("Open Codex App", symbol: "macwindow", action: #selector(openDefaultCodexApp)))
        return menu
    }

    private func profileMenu(_ profile: Profile) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(profileMenuItem("Open Codex App", symbol: "macwindow", action: #selector(openDesktop(_:)), profileID: profile.id))
        menu.addItem(.separator())
        menu.addItem(profileMenuItem("Backup", symbol: "archivebox", action: #selector(backupProfile(_:)), profileID: profile.id))
        menu.addItem(profileMenuItem("Remove...", symbol: "minus.circle", action: #selector(removeProfile(_:)), profileID: profile.id))
        return menu
    }

    private func menuItem(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    private func profileMenuItem(_ title: String, symbol: String, action: Selector, profileID: String) -> NSMenuItem {
        let item = menuItem(title, symbol: symbol, action: action)
        item.representedObject = profileID
        return item
    }

    private func profileMenuTitle(_ profile: Profile) -> String {
        profile.name
    }

    private func runMenuAction(_ action: () throws -> Void) {
        statusMenu?.cancelTracking()
        do {
            try action()
        } catch {
            showError(error)
        }
    }

    private func showSettingsWindow() {
        if let controller = settingsWindowController {
            presentSettingsWindow(controller)
            return
        }

        let controller = SettingsWindowController(store: store) { [weak self] in
            self?.rebuildMenu()
        }
        controller.onClose = { [weak self] in
            self?.settingsWindowController = nil
        }
        settingsWindowController = controller
        presentSettingsWindow(controller)
    }

    private func presentSettingsWindow(_ controller: SettingsWindowController) {
        controller.showWindow(nil)
        if let window = controller.window {
            window.setContentSize(NSSize(width: 780, height: 520))
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func settingsFromMenu() {
        statusMenu?.cancelTracking()
        showSettingsWindow()
    }

    @objc private func openProfilesFolderFromMenu() {
        statusMenu?.cancelTracking()
        NSWorkspace.shared.open(store.root)
    }

    @objc private func quitFromMenu() {
        statusMenu?.cancelTracking()
        quit()
    }

    @objc private func openDefaultCodexApp() {
        runMenuAction { try launcher.openDefaultDesktop() }
    }

    @objc private func openDesktop(_ sender: NSMenuItem) {
        withProfile(sender) { profile in
            try launcher.openDesktop(profile: profile)
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
        runMenuAction {
            guard confirm(
                title: "Remove Profile",
                message: "Remove \(id) from CodexN? Files remain on disk. No backup is created automatically."
            ) else {
                return
            }
            _ = try store.deleteProfile(id: id)
            rebuildMenu()
        }
    }

    private func withProfile(_ sender: NSMenuItem, action: (Profile) throws -> Void) {
        guard let id = sender.representedObject as? String else { return }
        runMenuAction {
            try action(try store.getProfile(id: id))
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

private final class MenuHostingView<Content: View>: NSHostingView<Content> {
    private var measuredSize: NSSize?

    override var allowsVibrancy: Bool { true }

    override var intrinsicContentSize: NSSize {
        measuredSize ?? super.intrinsicContentSize
    }

    func applyMeasuredSize(width: CGFloat, height: CGFloat) {
        measuredSize = NSSize(width: width, height: height)
        frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        invalidateIntrinsicContentSize()
        layoutSubtreeIfNeeded()
    }
}

private struct ProfileMenuHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CodexN")
                .font(.headline)
            Text("Switch Codex profiles and providers.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: 280, alignment: .leading)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(store: ProfileStore, onComplete: @escaping () -> Void) {
        let content = SettingsRootView(
            store: store,
            onClose: {},
            onComplete: onComplete
        )
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentViewController = hosting
        super.init(window: window)
        window.delegate = self
        hosting.rootView = SettingsRootView(
            store: store,
            onClose: { [weak self] in self?.close() },
            onComplete: { [weak self] in
                onComplete()
                self?.close()
            }
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case profiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .profiles: "Profiles"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .profiles: "person.2"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .profiles: .blue
        }
    }
}

private struct SettingsRootView: View {
    let store: ProfileStore
    let onClose: () -> Void
    let onComplete: () -> Void

    @State private var selection: SettingsPane = .general
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section("CodexN") {
                    ForEach(SettingsPane.allCases) { pane in
                        HStack(spacing: 9) {
                            SettingsIconChip(systemImage: pane.symbol, color: pane.color)
                            Text(pane.title)
                        }
                        .tag(pane)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 220)
        } detail: {
            switch selection {
            case .general:
                GeneralSettingsPane()
                    .navigationTitle(SettingsPane.general.title)
            case .profiles:
                AddProfileView(
                    store: store,
                    onCancel: onClose,
                    onComplete: onComplete
                )
                .navigationTitle(SettingsPane.profiles.title)
            }
        }
        .frame(minWidth: 720, idealWidth: 780, minHeight: 480, idealHeight: 520)
        .onAppear {
            columnVisibility = .doubleColumn
        }
    }
}

private enum LaunchAtLoginManager {
    static var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            true
        case .notRegistered, .notFound:
            false
        @unknown default:
            false
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            switch service.status {
            case .enabled, .requiresApproval:
                return
            case .notRegistered, .notFound:
                try service.register()
            @unknown default:
                try service.register()
            }
        } else {
            switch service.status {
            case .enabled, .requiresApproval:
                try service.unregister()
            case .notRegistered, .notFound:
                return
            @unknown default:
                try service.unregister()
            }
        }
    }
}

private struct GeneralSettingsPane: View {
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle(isOn: $launchAtLogin) {
                    SettingsRowLabel(
                        "Open at Login",
                        subtitle: "Start CodexN automatically when you sign in."
                    )
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .onAppear {
            launchAtLogin = LaunchAtLoginManager.isEnabled
        }
        .onChange(of: launchAtLogin) { _, enabled in
            updateLaunchAtLogin(enabled)
        }
        .alert("CodexN Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginManager.setEnabled(enabled)
            launchAtLogin = LaunchAtLoginManager.isEnabled
        } catch {
            errorMessage = String(describing: error)
            launchAtLogin = LaunchAtLoginManager.isEnabled
        }
    }
}

private enum AddProfileSelection: String, CaseIterable, Identifiable {
    case importDefault
    case oauth
    case apiKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .importDefault: "Import Default"
        case .oauth: "OAuth Login"
        case .apiKey: "API Key"
        }
    }

    var subtitle: String {
        switch self {
        case .importDefault: "Copy the current system Codex profile."
        case .oauth: "Create an empty isolated profile."
        case .apiKey: "Create a provider config with injected API key."
        }
    }

    var symbol: String {
        switch self {
        case .importDefault: "tray.and.arrow.down"
        case .oauth: "person.crop.circle"
        case .apiKey: "key"
        }
    }
}

private struct AddProfileView: View {
    let store: ProfileStore
    let onCancel: () -> Void
    let onComplete: () -> Void

    @State private var selection: AddProfileSelection = .oauth
    @State private var id = ""
    @State private var name = ""
    @State private var provider = ""
    @State private var model = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Add Profile") {
                Picker(selection: $selection) {
                    ForEach(AddProfileSelection.allCases) { item in
                        Text(item.title).tag(item)
                    }
                } label: {
                    SettingsRowLabel("Mode", subtitle: selection.subtitle)
                }
                .pickerStyle(.menu)

                LabeledContent("Profile ID") {
                    TextField("", text: $id)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                }

                LabeledContent("Display Name") {
                    TextField("", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                }
            }

            if selection == .apiKey {
                Section("Provider") {
                    LabeledContent("Model Provider") {
                        TextField("", text: $provider)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 320)
                    }
                    LabeledContent("Model Name") {
                        TextField("", text: $model)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 320)
                    }
                    LabeledContent("Base URL") {
                        TextField("", text: $baseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 320)
                    }
                    LabeledContent("API Key") {
                        SecureField("", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 320)
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button("Create") {
                        createProfile()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .alert("CodexN Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func createProfile() {
        do {
            let profileID = trimmed(id)
            let displayName = trimmed(name).isEmpty ? profileID : trimmed(name)
            switch selection {
            case .importDefault:
                _ = try store.importDefaultProfile(id: profileID, name: displayName)
            case .oauth:
                _ = try store.createProfile(id: profileID, name: displayName)
            case .apiKey:
                _ = try store.createAPIKeyProfile(
                    id: profileID,
                    name: displayName,
                    provider: trimmed(provider),
                    model: trimmed(model),
                    baseURL: trimmed(baseURL),
                    apiKey: apiKey
                )
            }
            onComplete()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

private struct SettingsIconChip: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.gradient)
            )
    }
}

private struct SettingsRowLabel: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsSection<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func trimmed(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
