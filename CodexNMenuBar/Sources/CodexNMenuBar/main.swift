import AppKit
import CodexNCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ProfileStore()
    private let launcher = Launcher()
    private let usageCache = CodexUsageCacheStore()
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var settingsWindowController: SettingsWindowController?
    private var usageRefreshTimer: Timer?
    private var usageRefreshTask: Task<Error?, Never>?

    private static let usageRefreshInterval: TimeInterval = 5 * 60

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
        startUsageRefreshLoop()
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageRefreshTimer?.invalidate()
        usageRefreshTask?.cancel()
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

        menu.addItem(menuItem("Default Codex", symbol: "house", action: #selector(openDefaultCodexApp)))

        if let loadError {
            let errorItem = NSMenuItem(title: "Failed to load profiles", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            errorItem.toolTip = loadError
            menu.addItem(errorItem)
        } else {
            profiles.forEach { profile in
                let item = profileMenuItem(
                    profileMenuTitle(profile),
                    symbol: profile.apiKeyEnvName == nil ? "person.crop.circle" : "key",
                    action: #selector(openDesktop(_:)),
                    profileID: profile.id
                )
                item.image = NSImage(
                    systemSymbolName: profile.apiKeyEnvName == nil ? "person.crop.circle" : "key",
                    accessibilityDescription: profile.name
                )
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        addUsageMenuItem(to: menu)
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings...", symbol: "gearshape", action: #selector(settingsFromMenu)))
        menu.addItem(menuItem("Open Profiles Folder", symbol: "folder", action: #selector(openProfilesFolderFromMenu)))
        menu.addItem(.separator())
        menu.addItem(menuItem("About...", symbol: "info.circle", action: #selector(aboutFromMenu)))
        menu.addItem(menuItem("Quit", symbol: "xmark.rectangle", action: #selector(quitFromMenu)))
    }

    private func menuItem(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    private func addUsageMenuItem(to menu: NSMenu) {
        let snapshot = (try? usageCache.read()) ?? nil
        let chart = TokenUsageMenuChart(snapshot: snapshot)
        let hosting = MenuHostingView(rootView: chart)
        let width: CGFloat = 300
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 1)
        let height = max(1, ceil(hosting.fittingSize.height))
        hosting.applyMeasuredSize(width: width, height: height)

        let item = NSMenuItem()
        item.view = hosting
        item.isEnabled = false
        menu.addItem(item)
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

    private func showSettingsWindow(selection: SettingsPane = .general) {
        if let controller = settingsWindowController {
            controller.select(selection)
            presentSettingsWindow(controller)
            return
        }

        let controller = SettingsWindowController(store: store, initialSelection: selection) { [weak self] in
            self?.refreshUsageCacheInBackground()
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

    private func startUsageRefreshLoop() {
        refreshUsageCacheInBackground()
        usageRefreshTimer?.invalidate()
        usageRefreshTimer = Timer.scheduledTimer(withTimeInterval: Self.usageRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshUsageCacheInBackground()
            }
        }
    }

    private func refreshUsageCacheInBackground() {
        guard usageRefreshTask == nil else { return }
        let root = store.root
        let task = Task.detached(priority: .utility) { () -> Error? in
            do {
                try Self.refreshUsageCache(root: root)
                return nil
            } catch {
                return error
            }
        }
        usageRefreshTask = task

        Task { @MainActor [weak self] in
            let error = await task.value
            guard let self else { return }
            self.usageRefreshTask = nil
            if error == nil {
                self.rebuildMenu()
            }
        }
    }

    nonisolated private static func refreshUsageCache(root: URL) throws {
        let store = ProfileStore(root: root)
        let managedProfiles = (try? store.listProfiles()) ?? []
        let usageProfiles = CodexUsageScanner.usageProfiles(managedProfiles: managedProfiles)
        let snapshot = try CodexUsageScanner().scanToday(profiles: usageProfiles)
        try CodexUsageCacheStore(root: root).write(snapshot)
    }

    @objc private func settingsFromMenu() {
        statusMenu?.cancelTracking()
        showSettingsWindow(selection: .general)
    }

    @objc private func aboutFromMenu() {
        statusMenu?.cancelTracking()
        showSettingsWindow(selection: .about)
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

    private func withProfile(_ sender: NSMenuItem, action: (Profile) throws -> Void) {
        guard let id = sender.representedObject as? String else { return }
        runMenuAction {
            try action(try store.getProfile(id: id))
        }
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

private struct TokenUsageMenuChart: View {
    let snapshot: CodexUsageSnapshot?

    @State private var hoveredProfileID: String?

    private let width: CGFloat = 300
    private let chartHeight: CGFloat = 76
    private let colors: [Color] = [
        Color(red: 0.26, green: 0.55, blue: 0.96),
        Color(red: 0.46, green: 0.72, blue: 0.38),
        Color(red: 0.94, green: 0.58, blue: 0.24),
        Color(red: 0.72, green: 0.40, blue: 0.86),
        Color(red: 0.25, green: 0.70, blue: 0.78),
        Color(red: 0.86, green: 0.34, blue: 0.42)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Token Usage")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(totalLabel)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let snapshot {
                if snapshot.profiles.isEmpty {
                    emptyState("No usage data today")
                } else {
                    chart(for: snapshot.profiles)
                }

                Text("Updated \(Self.timeString(snapshot.generatedAt))")
                    .font(.caption2)
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            } else {
                emptyState("Usage data is updating")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
    }

    private var totalLabel: String {
        guard let snapshot else { return "Updating" }
        return "\(Self.tokenString(snapshot.totalTokens)) today"
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    }

    private func chart(for profiles: [CodexUsageProfileSnapshot]) -> some View {
        let maxTokens = max(profiles.map(\.totalTokens).max() ?? 0, 1)
        let spacing: CGFloat = profiles.count > 6 ? 5 : 8
        let availableWidth = width - 24
        let barWidth = max(10, min(26, (availableWidth - CGFloat(max(0, profiles.count - 1)) * spacing) / CGFloat(max(1, profiles.count))))

        return HStack(alignment: .bottom, spacing: spacing) {
            ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                VStack(spacing: 5) {
                    Text(Self.shortTokenString(profile.totalTokens))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: max(28, barWidth + 8))

                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(colors[index % colors.count].gradient)
                            .frame(
                                width: barWidth,
                                height: barHeight(tokens: profile.totalTokens, maxTokens: maxTokens)
                            )
                            .shadow(
                                color: colors[index % colors.count].opacity(hoveredProfileID == profile.id ? 0.32 : 0),
                                radius: 4,
                                y: 1
                            )

                        if hoveredProfileID == profile.id {
                            Text(profile.id)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55))
                                )
                                .fixedSize()
                                .offset(y: -barHeight(tokens: profile.totalTokens, maxTokens: maxTokens) - 6)
                                .zIndex(1)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: max(32, barWidth + 12), height: 52, alignment: .bottom)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        hoveredProfileID = hovering ? profile.id : (hoveredProfileID == profile.id ? nil : hoveredProfileID)
                    }
                    .help("\(profile.id)\n\(Self.tokenString(profile.totalTokens)) today")
                    .accessibilityLabel(profile.name)
                    .accessibilityValue(Self.tokenString(profile.totalTokens))
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(maxWidth: .infinity, minHeight: chartHeight, maxHeight: chartHeight, alignment: .bottom)
    }

    private func barHeight(tokens: UInt64, maxTokens: UInt64) -> CGFloat {
        guard tokens > 0 else { return 2 }
        let ratio = Double(tokens) / Double(maxTokens)
        return max(6, CGFloat(ratio) * 48)
    }

    private static func shortTokenString(_ value: UInt64) -> String {
        if value == 0 { return "0" }
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.0fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private static func tokenString(_ value: UInt64) -> String {
        if value >= 1_000_000 {
            return String(format: "%.2fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

@MainActor
private final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let store: ProfileStore
    private let onComplete: () -> Void
    private let hosting: NSHostingController<SettingsRootView>

    init(store: ProfileStore, initialSelection: SettingsPane, onComplete: @escaping () -> Void) {
        self.store = store
        self.onComplete = onComplete
        let content = SettingsRootView(
            store: store,
            initialSelection: initialSelection,
            onClose: {},
            onComplete: onComplete
        )
        self.hosting = NSHostingController(rootView: content)
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
        select(initialSelection)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func select(_ selection: SettingsPane) {
        hosting.rootView = SettingsRootView(
            store: store,
            initialSelection: selection,
            onClose: { [weak self] in self?.close() },
            onComplete: { [weak self] in
                self?.onComplete()
            }
        )
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case profiles
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .profiles: "Profiles"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .profiles: "person.2"
        case .about: "info.circle"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .profiles: .blue
        case .about: .indigo
        }
    }
}

private struct SettingsRootView: View {
    let store: ProfileStore
    let initialSelection: SettingsPane
    let onClose: () -> Void
    let onComplete: () -> Void

    @State private var selection: SettingsPane

    init(
        store: ProfileStore,
        initialSelection: SettingsPane,
        onClose: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.store = store
        self.initialSelection = initialSelection
        self.onClose = onClose
        self.onComplete = onComplete
        self._selection = State(initialValue: initialSelection)
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 200)
                .background(.bar)

            Divider()

            SettingsDetailPane(title: selection.title) {
                switch selection {
                case .general:
                    GeneralSettingsPane()
                case .profiles:
                    ProfilesSettingsPane(
                        store: store,
                        onCancel: onClose,
                        onProfilesChanged: onComplete
                    )
                case .about:
                    AboutSettingsPane()
                }
            }
        }
        .frame(minWidth: 720, idealWidth: 780, minHeight: 480, idealHeight: 520)
        .onAppear {
            selection = initialSelection
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CodexN")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 6)

            ForEach(SettingsPane.allCases) { pane in
                Button {
                    selection = pane
                } label: {
                    HStack(spacing: 9) {
                        SettingsIconChip(systemImage: pane.symbol, color: pane.color)
                        Text(pane.title)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selection == pane ? Color.accentColor.opacity(0.16) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Spacer()
        }
    }
}

private struct SettingsDetailPane<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)

            Divider()

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

private struct AboutSettingsPane: View {
    private let appName = "CodexN"
    private let repositoryURL = URL(string: "https://github.com/NeoAgentman/CodexN")!

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(spacing: 3) {
                        Text(appName)
                            .font(.title2.weight(.semibold))
                        Text("Codex profile launcher")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }

            Section("Version") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: buildNumber)
                LabeledContent("Built", value: buildDate)
            }

            Section("Project") {
                Button {
                    NSWorkspace.shared.open(repositoryURL)
                } label: {
                    HStack {
                        SettingsRowLabel("GitHub", subtitle: "NeoAgentman/CodexN")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        infoValue("CFBundleShortVersionString", fallback: "0.1.7")
    }

    private var buildNumber: String {
        infoValue("CFBundleVersion", fallback: "Development")
    }

    private var buildDate: String {
        infoValue("CodexNBuildDate", fallback: "Development build")
    }

    private func infoValue(_ key: String, fallback: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else {
            return fallback
        }
        return value
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

private struct ProfilesSettingsPane: View {
    let store: ProfileStore
    let onCancel: () -> Void
    let onProfilesChanged: () -> Void

    @State private var profiles: [Profile] = []
    @State private var selection: AddProfileSelection = .oauth
    @State private var id = ""
    @State private var name = ""
    @State private var provider = ""
    @State private var model = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var pendingRemoval: Profile?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Profiles") {
                if profiles.isEmpty {
                    Text("No profiles")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profiles) { profile in
                        HStack(spacing: 10) {
                            SettingsIconChip(
                                systemImage: profile.apiKeyEnvName == nil ? "person.crop.circle" : "key",
                                color: profile.apiKeyEnvName == nil ? .blue : .orange
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                Text(profile.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                pendingRemoval = profile
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .help("Remove Profile")
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

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
        .onAppear(perform: loadProfiles)
        .alert("Remove Profile", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        )) {
            Button("Remove", role: .destructive) {
                removePendingProfile()
            }
            Button("Cancel", role: .cancel) {
                pendingRemoval = nil
            }
        } message: {
            Text(removeConfirmationMessage)
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

    private var removeConfirmationMessage: String {
        guard let pendingRemoval else { return "" }
        return "Remove \(pendingRemoval.id) from CodexN? Files remain on disk."
    }

    private func loadProfiles() {
        do {
            profiles = try store.listProfiles()
        } catch {
            profiles = []
            errorMessage = String(describing: error)
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
            resetAddForm()
            loadProfiles()
            onProfilesChanged()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func removePendingProfile() {
        guard let profile = pendingRemoval else { return }
        do {
            _ = try store.deleteProfile(id: profile.id)
            pendingRemoval = nil
            loadProfiles()
            onProfilesChanged()
        } catch {
            pendingRemoval = nil
            errorMessage = String(describing: error)
        }
    }

    private func resetAddForm() {
        id = ""
        name = ""
        provider = ""
        model = ""
        baseURL = ""
        apiKey = ""
        selection = .oauth
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
