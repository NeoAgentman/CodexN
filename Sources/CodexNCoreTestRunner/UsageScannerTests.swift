import Foundation
import CodexNCore

extension TestRunner {
    static func scansTodayUsageFromCodexHomes() throws {
        let root = try temporaryDirectory()
        let codexHome = root.appending(path: "work/codex-home")
        let sessions = codexHome.appending(path: "sessions")
        let archived = codexHome.appending(path: "archived_sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 12))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        try [
            tokenLine(timestamp: yesterday, total: usage(input: 80, cached: 10, output: 20, total: 100)),
            tokenLine(timestamp: today, total: usage(input: 130, cached: 20, output: 30, total: 160)),
            tokenLine(timestamp: today, last: usage(input: 7, cached: 2, output: 3, total: 10), total: usage(input: 137, cached: 22, output: 33, total: 170))
        ].joined(separator: "\n").write(
            to: sessions.appending(path: "session.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try tokenLine(timestamp: today, last: usage(input: 4, cached: 1, output: 5, total: 9))
            .write(to: archived.appending(path: "archived-only.jsonl"), atomically: true, encoding: .utf8)
        try tokenLine(timestamp: today, last: usage(input: 999, cached: 0, output: 1, total: 1_000))
            .write(to: archived.appending(path: "session.jsonl"), atomically: true, encoding: .utf8)

        let scanner = CodexUsageScanner()
        let snapshot = try scanner.scanToday(
            profiles: [CodexUsageProfile(id: "work", name: "Work", codexHome: codexHome)],
            date: today,
            calendar: calendar
        )

        try expect(snapshot.dayKey == "2027-01-01", "snapshot should use local day key")
        try expect(snapshot.totalTokens == 79, "today total should add cumulative delta, last usage, and archived-only usage")
        try expect(snapshot.profiles.count == 1, "should include one profile")
        try expect(snapshot.profiles[0].totalTokens == 79, "profile total should be 79")
        try expect(snapshot.profiles[0].cachedInputTokens == 13, "cached input should add delta and last usage")
    }

    static func scansRecentlyModifiedOlderCodexSessionPartitionsOnly() throws {
        let root = try temporaryDirectory()
        let codexHome = root.appending(path: "work/codex-home")
        let sessions = codexHome.appending(path: "sessions")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2027, month: 3, day: 11, hour: 12))!
        let recentlyModified = calendar.date(byAdding: .hour, value: -12, to: today)!
        let staleModified = calendar.date(byAdding: .day, value: -10, to: today)!

        let activeOldPartition = sessions.appending(path: "2027/03/01")
        let staleOldPartition = sessions.appending(path: "2027/03/02")
        try FileManager.default.createDirectory(at: activeOldPartition, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staleOldPartition, withIntermediateDirectories: true)

        let activeFile = activeOldPartition.appending(path: "rollout-2027-03-01T09-00-00-active.jsonl")
        let staleFile = staleOldPartition.appending(path: "rollout-2027-03-02T09-00-00-stale.jsonl")
        try tokenLine(timestamp: today, last: usage(input: 11, cached: 2, output: 3, total: 14))
            .write(to: activeFile, atomically: true, encoding: .utf8)
        try tokenLine(timestamp: today, last: usage(input: 999, cached: 0, output: 1, total: 1_000))
            .write(to: staleFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: recentlyModified], ofItemAtPath: activeFile.path)
        try FileManager.default.setAttributes([.modificationDate: staleModified], ofItemAtPath: staleFile.path)

        let scanner = CodexUsageScanner()
        let snapshot = try scanner.scanToday(
            profiles: [CodexUsageProfile(id: "work", name: "Work", codexHome: codexHome)],
            date: today,
            calendar: calendar
        )

        try expect(snapshot.totalTokens == 14, "recently modified older partitions should be scanned without full recursion")
        try expect(snapshot.profiles[0].inputTokens == 11, "stale older partitions should not contribute")
    }

    static func computesUsageListBarWidths() throws {
        try expect(
            TokenUsageChartLayout.horizontalBarWidth(tokens: 0, maxTokens: 100, availableWidth: 120, minVisibleWidth: 6) == 0,
            "zero usage should not show a usage list bar"
        )
        try expect(
            TokenUsageChartLayout.horizontalBarWidth(tokens: 100, maxTokens: 100, availableWidth: 120, minVisibleWidth: 6) == 120,
            "max usage should fill usage list bar width"
        )
        try expect(
            TokenUsageChartLayout.horizontalBarWidth(tokens: 1, maxTokens: 100, availableWidth: 120, minVisibleWidth: 6) == 6,
            "nonzero tiny usage should keep a minimum visible usage list bar"
        )
    }

    static func formatsTokenUsageValues() throws {
        try expect(TokenUsageFormatting.shortTokenString(0) == "0", "zero short token usage should be plain")
        try expect(TokenUsageFormatting.shortTokenString(11_000) == "11K", "short token usage should abbreviate thousands")
        try expect(TokenUsageFormatting.shortTokenString(100_140_000) == "100.1M", "short token usage should abbreviate millions")
        try expect(TokenUsageFormatting.shortTokenString(1_234_000_000) == "1.2B", "short token usage should abbreviate billions")

        try expect(TokenUsageFormatting.tokenString(900) == "900", "token usage below one thousand should be plain")
        try expect(TokenUsageFormatting.tokenString(11_000) == "11.0K", "token usage should abbreviate thousands")
        try expect(TokenUsageFormatting.tokenString(100_140_000) == "100.14M", "token usage should abbreviate millions")
        try expect(TokenUsageFormatting.tokenString(1_234_000_000) == "1.23B", "token usage should abbreviate billions")
    }

    static func writesAndReadsUsageCache() throws {
        let root = try temporaryDirectory()
        let cache = CodexUsageCacheStore(root: root)
        let snapshot = CodexUsageSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_798_416_005),
            dayKey: "2027-01-01",
            profiles: [
                CodexUsageProfileSnapshot(
                    id: "work",
                    name: "Work",
                    inputTokens: 10,
                    cachedInputTokens: 2,
                    outputTokens: 5,
                    reasoningOutputTokens: 1,
                    totalTokens: 15,
                    errorMessage: nil
                )
            ]
        )

        try cache.write(snapshot)
        let loaded = try require(try cache.read(), "usage cache should load")

        try expect(loaded.dayKey == "2027-01-01", "cache should preserve day key")
        try expect(loaded.totalTokens == 15, "cache should preserve computed total")
        try expect(loaded.profiles.map(\.id) == ["work"], "cache should preserve profile ids")
    }

    static func usage(input: UInt64, cached: UInt64, output: UInt64, reasoning: UInt64 = 0, total: UInt64) -> String {
        #"{"input_tokens": \#(input), "cached_input_tokens": \#(cached), "output_tokens": \#(output), "reasoning_output_tokens": \#(reasoning), "total_tokens": \#(total)}"#
    }

    static func tokenLine(timestamp: Date, last: String? = nil, total: String? = nil) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let infoParts = [
            last.map { "\"last_token_usage\": \($0)" },
            total.map { "\"total_token_usage\": \($0)" }
        ].compactMap(\.self).joined(separator: ",")
        return """
        {"timestamp":"\(formatter.string(from: timestamp))","type":"event_msg","payload":{"type":"token_count","info":{\(infoParts)}}}
        """
    }
}
