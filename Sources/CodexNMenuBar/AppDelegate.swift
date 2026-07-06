import AppKit
import Carbon
import CodexNCore

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
    private var focusedProfileTimer: Timer?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var workspaceTerminationObserver: NSObjectProtocol?
    private var focusedProfileLabel: FocusedCodexProfileLabel = .none
    private var usageSnapshot: CodexUsageSnapshot?
    private var displayedStatusTitle: MenuBarUsageTitle?

    private static let usageRefreshInterval: TimeInterval = 30 * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            configureStatusButton(button)
        }
        statusItem = item

        let menu = NSMenu()
        menu.delegate = self
        statusMenu = menu
        statusItem?.menu = menu
        reloadUsageSnapshotFromCache()
        rebuildMenu()
        startUsageRefreshLoop()
        startFocusedProfileTitleUpdates()
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageRefreshTimer?.invalidate()
        usageRefreshTask?.cancel()
        focusedProfileTimer?.invalidate()
        stopFocusedProfileTitleObservers()
    }

    func menuWillOpen(_ menu: NSMenu) {
        reloadUsageSnapshotFromCache()
        updateFocusedProfileTitle()
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

        menu.addItem(menuItem("Open Default Codex", symbol: "house", action: #selector(openDefaultCodexApp)))

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
        menu.addItem(addProfileMenuItem())

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

    private func addProfileMenuItem() -> NSMenuItem {
        let title = "Add Profile..."
        let item = menuItem(title, symbol: "plus.circle", action: #selector(addProfileFromMenu))
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            ]
        )
        return item
    }

    private func addUsageMenuItem(to menu: NSMenu) {
        let chart = TokenUsageMenuChart(snapshot: usageSnapshot)
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
        "Open \(profile.name)"
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

    private func startFocusedProfileTitleUpdates() {
        updateFocusedProfileTitle()
        focusedProfileTimer?.invalidate()
        focusedProfileTimer = Timer.scheduledTimer(withTimeInterval: FocusedCodexProfileResolver.fallbackRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateFocusedProfileTitle()
            }
        }

        stopFocusedProfileTitleObservers()
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateFocusedProfileTitle()
            }
        }
        workspaceTerminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateFocusedProfileTitle()
            }
        }
    }

    private func stopFocusedProfileTitleObservers() {
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
            self.workspaceActivationObserver = nil
        }
        if let workspaceTerminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceTerminationObserver)
            self.workspaceTerminationObserver = nil
        }
    }

    private func updateFocusedProfileTitle() {
        let snapshot = focusedCodexProcessSnapshot()
        let profiles = (try? store.listProfiles()) ?? []
        let label = FocusedCodexProfileResolver.resolve(snapshot: snapshot, profiles: profiles)
        focusedProfileLabel = label
        applyStatusTitle(for: label)
    }

    private func applyStatusTitle(for label: FocusedCodexProfileLabel) {
        let title = MenuBarUsageTitleFormatter.title(for: label, snapshot: usageSnapshot)
        guard title != displayedStatusTitle else { return }
        displayedStatusTitle = title

        guard let highlightedSegment = title.highlightedSegment,
              let range = title.text.range(of: highlightedSegment, options: .backwards) else {
            statusItem?.button?.attributedTitle = NSAttributedString(string: title.text)
            return
        }

        let attributedTitle = NSMutableAttributedString(
            string: title.text,
            attributes: [
                .font: NSFont.menuBarFont(ofSize: 0),
                .foregroundColor: NSColor.labelColor
            ]
        )
        attributedTitle.addAttributes(
            [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                .foregroundColor: NSColor.controlAccentColor
            ],
            range: NSRange(range, in: title.text)
        )
        statusItem?.button?.attributedTitle = attributedTitle
    }

    private func reloadUsageSnapshotFromCache() {
        usageSnapshot = (try? usageCache.read()) ?? nil
    }

    private func configureStatusButton(_ button: NSStatusBarButton) {
        button.image = Self.menuBarIcon()
        button.imagePosition = .imageLeft
        button.imageScaling = .scaleProportionallyDown
        button.attributedTitle = NSAttributedString(string: "")
        button.toolTip = "Codex profile launcher"
    }

    private static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let mark = NSBezierPath()
            mark.lineWidth = 2.2
            mark.lineCapStyle = .round
            mark.lineJoinStyle = .round
            mark.move(to: NSPoint(x: 4.4, y: 4.1))
            mark.line(to: NSPoint(x: 4.4, y: 13.9))
            mark.line(to: NSPoint(x: 13.6, y: 4.1))
            mark.line(to: NSPoint(x: 13.6, y: 13.9))
            mark.stroke()

            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 2.3, y: 2.0, width: 2.8, height: 2.8)).fill()
            NSBezierPath(ovalIn: NSRect(x: 12.9, y: 13.2, width: 2.8, height: 2.8)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func focusedCodexProcessSnapshot() -> FocusedCodexProcessSnapshot? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        let shouldReadProcessArguments = FocusedCodexProfileResolver.shouldReadProcessArguments(
            bundleIdentifier: application.bundleIdentifier,
            localizedName: application.localizedName,
            executablePath: application.executableURL?.path
        )
        let processInfo = shouldReadProcessArguments
            ? FocusedCodexProcessArgumentsReader.read(pid: application.processIdentifier)
            : (arguments: [], environment: [:])
        return FocusedCodexProcessSnapshot(
            pid: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            localizedName: application.localizedName,
            executablePath: application.executableURL?.path,
            arguments: processInfo.arguments,
            environment: processInfo.environment
        )
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
                self.reloadUsageSnapshotFromCache()
                self.rebuildMenu()
                self.applyStatusTitle(for: self.focusedProfileLabel)
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

    @objc private func addProfileFromMenu() {
        statusMenu?.cancelTracking()
        showSettingsWindow(selection: .profiles)
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
        runMenuAction {
            if !(try focusOrReopenRunningCodexApp(for: .defaultCodex, reopen: { try launcher.reopenDefaultDesktop() })) {
                try launcher.openDefaultDesktop()
            }
        }
    }

    @objc private func openDesktop(_ sender: NSMenuItem) {
        withProfile(sender) { profile in
            if !(try focusOrReopenRunningCodexApp(for: .profile(id: profile.id), reopen: { try launcher.openDesktop(profile: profile) })) {
                try launcher.openDesktop(profile: profile)
            }
        }
    }

    private func focusOrReopenRunningCodexApp(for target: FocusedCodexProfileLabel, reopen: () throws -> Void) throws -> Bool {
        let profiles = (try? store.listProfiles()) ?? []
        let candidates = runningCodexApplications()
        let plan = FocusedCodexProfileResolver.activationPlan(
            for: target,
            snapshots: candidates.map(\.snapshot),
            profiles: profiles
        )
        switch plan {
        case .launch:
            return false
        case .activate(let pid):
            return activateRunningApplication(pid: pid, candidates: candidates)
        case .reopen(let pid):
            do {
                try reopenRunningApplication(pid: pid)
            } catch {
                try reopen()
            }
            _ = activateRunningApplication(pid: pid, candidates: candidates)
            scheduleVisibleCodexActivation(for: target)
            return true
        }
    }

    private func reopenRunningApplication(pid: Int32) throws {
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        _ = try event.sendEvent(options: [.noReply], timeout: 1)
    }

    private func activateVisibleCodexApp(for target: FocusedCodexProfileLabel) {
        let profiles = (try? store.listProfiles()) ?? []
        let candidates = runningCodexApplications().filter(\.snapshot.hasVisibleWindow)
        let selected = FocusedCodexProfileResolver.matchingCodexProcessSnapshot(
            for: target,
            snapshots: candidates.map(\.snapshot.process),
            profiles: profiles
        )
        guard let selected,
              let application = candidates.first(where: { $0.snapshot.process.pid == selected.pid })?.application else { return }
        _ = application.activate(options: [.activateAllWindows])
    }

    private func scheduleVisibleCodexActivation(for target: FocusedCodexProfileLabel) {
        [0.35, 1.0].forEach { delay in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.activateVisibleCodexApp(for: target)
            }
        }
    }

    private func activateRunningApplication(
        pid: Int32,
        candidates: [(application: NSRunningApplication, snapshot: RunningCodexProcessSnapshot)]
    ) -> Bool {
        guard let application = candidates.first(where: { $0.snapshot.process.pid == pid })?.application else { return false }
        return application.activate(options: [.activateAllWindows])
    }

    private func runningCodexApplications() -> [(application: NSRunningApplication, snapshot: RunningCodexProcessSnapshot)] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            let shouldReadProcessArguments = FocusedCodexProfileResolver.shouldReadProcessArguments(
                bundleIdentifier: application.bundleIdentifier,
                localizedName: application.localizedName,
                executablePath: application.executableURL?.path
            )
            guard shouldReadProcessArguments else { return nil }

            let processArguments = FocusedCodexProcessArgumentsReader.read(pid: application.processIdentifier)
            let snapshot = FocusedCodexProcessSnapshot(
                pid: application.processIdentifier,
                bundleIdentifier: application.bundleIdentifier,
                localizedName: application.localizedName,
                executablePath: application.executableURL?.path,
                arguments: processArguments.arguments,
                environment: processArguments.environment
            )
            return (
                application,
                RunningCodexProcessSnapshot(
                    process: snapshot,
                    hasVisibleWindow: hasVisibleWindow(pid: application.processIdentifier)
                )
            )
        }
    }

    private func hasVisibleWindow(pid: Int32) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return true
        }
        return windows.contains { window in
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? NSNumber,
                  ownerPID.int32Value == pid,
                  let layer = window[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0 else {
                return false
            }
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? NSNumber,
                  let height = bounds["Height"] as? NSNumber else {
                return true
            }
            return width.doubleValue > 1 && height.doubleValue > 1
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
