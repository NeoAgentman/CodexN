import AppKit
import CodexNCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
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
