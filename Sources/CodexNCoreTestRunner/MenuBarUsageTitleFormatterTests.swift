import Foundation
import CodexNCore

extension TestRunner {
    static func formatsMenuBarUsageTitles() throws {
        let snapshot = CodexUsageSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_798_416_005),
            dayKey: "2027-01-01",
            profiles: [
                CodexUsageProfileSnapshot(
                    id: "default-codex",
                    name: "Default Codex",
                    inputTokens: 1_000,
                    cachedInputTokens: 0,
                    outputTokens: 2_000,
                    reasoningOutputTokens: 0,
                    totalTokens: 3_000,
                    errorMessage: nil
                ),
                CodexUsageProfileSnapshot(
                    id: "zl",
                    name: "ZL",
                    inputTokens: 7_000,
                    cachedInputTokens: 0,
                    outputTokens: 1_400,
                    reasoningOutputTokens: 0,
                    totalTokens: 8_400,
                    errorMessage: nil
                )
            ]
        )

        let totalTitle = MenuBarUsageTitleFormatter.title(for: .none, snapshot: snapshot)
        try expect(totalTitle.text == "11K", "unfocused menu bar title should show total usage")
        try expect(totalTitle.highlightedSegment == nil, "unfocused usage title should not highlight a profile")

        let defaultTitle = MenuBarUsageTitleFormatter.title(for: .defaultCodex, snapshot: snapshot)
        try expect(defaultTitle.text == "Default 3K", "default Codex title should show default profile usage")
        try expect(defaultTitle.highlightedSegment == "Default", "default Codex title should highlight Default")

        let profileTitle = MenuBarUsageTitleFormatter.title(for: .profile(id: "zl"), snapshot: snapshot)
        try expect(profileTitle.text == "zl 8K", "focused profile title should show profile usage")
        try expect(profileTitle.highlightedSegment == "zl", "focused profile title should highlight profile id")

        let missingProfileTitle = MenuBarUsageTitleFormatter.title(for: .profile(id: "missing"), snapshot: snapshot)
        try expect(missingProfileTitle.text == "missing 0", "missing profile usage should show zero tokens")
        try expect(missingProfileTitle.highlightedSegment == "missing", "missing profile title should still highlight profile id")

        let noSnapshotTitle = MenuBarUsageTitleFormatter.title(for: .profile(id: "zl"), snapshot: nil)
        try expect(noSnapshotTitle.text == "zl", "missing usage cache should preserve existing focused profile title")
        try expect(noSnapshotTitle.highlightedSegment == "zl", "missing usage cache should preserve profile highlight")
    }
}
