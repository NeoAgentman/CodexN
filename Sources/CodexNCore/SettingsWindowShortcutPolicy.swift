import Foundation

public enum SettingsWindowShortcutPolicy {
    public static func shouldCloseWindow(
        charactersIgnoringModifiers: String?,
        hasCommandOnlyModifier: Bool
    ) -> Bool {
        hasCommandOnlyModifier && charactersIgnoringModifiers?.lowercased() == "w"
    }
}
