import CodexNCore

extension TestRunner {
    static func recognizesSettingsWindowCloseShortcut() throws {
        try expect(
            SettingsWindowShortcutPolicy.shouldCloseWindow(
                charactersIgnoringModifiers: "w",
                hasCommandOnlyModifier: true
            ),
            "Command-W should close the settings window"
        )
        try expect(
            SettingsWindowShortcutPolicy.shouldCloseWindow(
                charactersIgnoringModifiers: "W",
                hasCommandOnlyModifier: true
            ),
            "uppercase W should still be recognized as the settings window close shortcut"
        )
        try expect(
            !SettingsWindowShortcutPolicy.shouldCloseWindow(
                charactersIgnoringModifiers: "w",
                hasCommandOnlyModifier: false
            ),
            "plain W should not close the settings window"
        )
        try expect(
            !SettingsWindowShortcutPolicy.shouldCloseWindow(
                charactersIgnoringModifiers: "q",
                hasCommandOnlyModifier: true
            ),
            "Command-Q should not be handled by the settings window close shortcut"
        )
    }
}
