import Foundation

public struct MenuBarUsageTitle: Equatable {
    public let text: String
    public let highlightedSegment: String?
}

public enum MenuBarUsageTitleFormatter {
    public static func title(
        for label: FocusedCodexProfileLabel,
        snapshot: CodexUsageSnapshot?
    ) -> MenuBarUsageTitle {
        guard let snapshot else {
            return MenuBarUsageTitle(
                text: FocusedCodexProfileResolver.menuBarProfileText(for: label),
                highlightedSegment: FocusedCodexProfileResolver.menuBarHighlightedSegment(for: label)
            )
        }

        switch label {
        case .none:
            return MenuBarUsageTitle(
                text: TokenUsageFormatting.shortTokenString(snapshot.totalTokens),
                highlightedSegment: nil
            )
        case .defaultCodex:
            return focusedTitle(label: label, profileID: CodexUsageScanner.defaultUsageProfile().id, snapshot: snapshot)
        case .profile(let id):
            return focusedTitle(label: label, profileID: id, snapshot: snapshot)
        }
    }

    private static func focusedTitle(
        label: FocusedCodexProfileLabel,
        profileID: String,
        snapshot: CodexUsageSnapshot
    ) -> MenuBarUsageTitle {
        let profileText = FocusedCodexProfileResolver.menuBarProfileText(for: label)
        let tokens = snapshot.profiles.first(where: { $0.id == profileID })?.totalTokens ?? 0
        return MenuBarUsageTitle(
            text: "\(profileText) \(TokenUsageFormatting.shortTokenString(tokens))",
            highlightedSegment: FocusedCodexProfileResolver.menuBarHighlightedSegment(for: label)
        )
    }
}
