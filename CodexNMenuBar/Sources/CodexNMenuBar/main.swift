import AppKit
import CodexNCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ProfileStore()
    private let launcher = Launcher()
    private var statusItem: NSStatusItem?

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
        menu.addItem(menuItem("Import Default...", action: #selector(importDefaultProfile)))
        menu.addItem(menuItem("New Empty Profile...", action: #selector(newEmptyProfile)))
        menu.addItem(menuItem("Refresh", action: #selector(refreshMenu)))
        menu.addItem(.separator())

        do {
            let profiles = try store.listProfiles()
            if profiles.isEmpty {
                let empty = NSMenuItem(title: "No profiles", action: nil, keyEquivalent: "")
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

    @objc private func importDefaultProfile() {
        guard let input = promptForProfile(title: "Import Default Profile", defaultID: "default") else { return }
        do {
            _ = try store.importDefaultProfile(id: input.id, name: input.name)
            rebuildMenu()
        } catch {
            showError(error)
        }
    }

    @objc private func newEmptyProfile() {
        guard let input = promptForProfile(title: "New Empty Profile", defaultID: "work") else { return }
        do {
            _ = try store.createProfile(id: input.id, name: input.name)
            rebuildMenu()
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
        guard confirm(title: "Remove Profile", message: "Remove \(id) from CodexN? Files remain on disk after a backup is created.") else {
            return
        }
        do {
            _ = try store.backupProfile(id: id)
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

    private func promptForProfile(title: String, defaultID: String) -> (id: String, name: String)? {
        let idField = NSTextField(string: defaultID)
        let nameField = NSTextField(string: defaultID)
        let stack = NSStackView(views: [
            label("Profile ID"),
            idField,
            label("Display Name"),
            nameField
        ])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.setFrameSize(NSSize(width: 280, height: 96))

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Profile ID may contain letters, numbers, dot, underscore, or dash."
        alert.accessoryView = stack
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let id = idField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return (id, name.isEmpty ? id : name)
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        return label
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
