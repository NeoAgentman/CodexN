import Foundation

public struct CodexUsageProfile: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let codexHome: URL

    public init(id: String, name: String, codexHome: URL) {
        self.id = id
        self.name = name
        self.codexHome = codexHome
    }
}

public struct CodexUsageProfileSnapshot: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let inputTokens: UInt64
    public let cachedInputTokens: UInt64
    public let outputTokens: UInt64
    public let reasoningOutputTokens: UInt64
    public let totalTokens: UInt64
    public let errorMessage: String?

    public init(
        id: String,
        name: String,
        inputTokens: UInt64,
        cachedInputTokens: UInt64,
        outputTokens: UInt64,
        reasoningOutputTokens: UInt64,
        totalTokens: UInt64,
        errorMessage: String?
    ) {
        self.id = id
        self.name = name
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
        self.errorMessage = errorMessage
    }
}

public struct CodexUsageSnapshot: Codable, Equatable {
    public let version: Int
    public let generatedAt: Date
    public let dayKey: String
    public let profiles: [CodexUsageProfileSnapshot]
    public let totalTokens: UInt64

    public init(
        version: Int = 1,
        generatedAt: Date,
        dayKey: String,
        profiles: [CodexUsageProfileSnapshot],
        totalTokens: UInt64? = nil
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.dayKey = dayKey
        self.profiles = profiles
        self.totalTokens = totalTokens ?? profiles.reduce(0) { $0 + $1.totalTokens }
    }
}

public final class CodexUsageCacheStore {
    public let cacheURL: URL
    private let fileManager: FileManager

    public init(root: URL = ProfileStore.defaultRoot(), fileManager: FileManager = .default) {
        self.cacheURL = root.appending(path: "usage-cache.json")
        self.fileManager = fileManager
    }

    public func read() throws -> CodexUsageSnapshot? {
        guard fileManager.fileExists(atPath: cacheURL.path) else { return nil }
        let data = try Data(contentsOf: cacheURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CodexUsageSnapshot.self, from: data)
    }

    public func write(_ snapshot: CodexUsageSnapshot) throws {
        try fileManager.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: cacheURL, options: [.atomic])
    }
}

public struct CodexUsageScanner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scanToday(
        profiles: [CodexUsageProfile],
        date: Date = Date(),
        calendar: Calendar = .current
    ) throws -> CodexUsageSnapshot {
        let dayKey = Self.dayKey(for: date, calendar: calendar)
        let profileSnapshots = profiles.map { profile in
            do {
                let totals = try scanProfile(profile, date: date, calendar: calendar)
                return CodexUsageProfileSnapshot(
                    id: profile.id,
                    name: profile.name,
                    inputTokens: totals.inputTokens,
                    cachedInputTokens: totals.cachedInputTokens,
                    outputTokens: totals.outputTokens,
                    reasoningOutputTokens: totals.reasoningOutputTokens,
                    totalTokens: totals.totalTokens,
                    errorMessage: nil
                )
            } catch {
                return CodexUsageProfileSnapshot(
                    id: profile.id,
                    name: profile.name,
                    inputTokens: 0,
                    cachedInputTokens: 0,
                    outputTokens: 0,
                    reasoningOutputTokens: 0,
                    totalTokens: 0,
                    errorMessage: String(describing: error)
                )
            }
        }
        return CodexUsageSnapshot(generatedAt: date, dayKey: dayKey, profiles: profileSnapshots)
    }

    public static func defaultUsageProfile() -> CodexUsageProfile {
        CodexUsageProfile(
            id: "default-codex",
            name: "Default Codex",
            codexHome: ProfileStore.defaultCodexHome()
        )
    }

    public static func usageProfiles(defaultIncluded: Bool = true, managedProfiles: [Profile]) -> [CodexUsageProfile] {
        var profiles: [CodexUsageProfile] = defaultIncluded ? [defaultUsageProfile()] : []
        profiles.append(contentsOf: managedProfiles.map {
            CodexUsageProfile(id: $0.id, name: $0.name, codexHome: $0.codexHome)
        })
        return profiles
    }

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func scanProfile(_ profile: CodexUsageProfile, date: Date, calendar: Calendar) throws -> CodexUsageTotals {
        var totals = CodexUsageTotals()
        for file in collectUsageFiles(codexHome: profile.codexHome) {
            totals.add(try scanUsageFile(file, date: date, calendar: calendar))
        }
        return totals
    }

    private func collectUsageFiles(codexHome: URL) -> [URL] {
        let sessions = codexHome.appending(path: "sessions")
        let archivedSessions = codexHome.appending(path: "archived_sessions")
        var directories: [URL] = []
        if isDirectory(sessions) {
            directories.append(sessions)
        }
        if isDirectory(archivedSessions) {
            directories.append(archivedSessions)
        }
        if directories.isEmpty, isDirectory(codexHome) {
            directories.append(codexHome)
        }

        var seenRelativePaths = Set<String>()
        var files: [URL] = []
        for directory in directories {
            for file in collectJSONLFiles(in: directory) {
                let key = relativePath(file, from: directory)
                if seenRelativePaths.insert(key).inserted {
                    files.append(file)
                }
            }
        }
        return files
    }

    private func collectJSONLFiles(in directory: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let file as URL in enumerator where file.pathExtension == "jsonl" {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile != false {
                files.append(file)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func scanUsageFile(_ file: URL, date: Date, calendar: Calendar) throws -> CodexUsageTotals {
        let data = try Data(contentsOf: file)
        var totals = CodexUsageTotals()
        var previousCumulative: CodexUsageTotals?
        for rawLine in data.split(separator: UInt8(ascii: "\n")) {
            let line = Data(rawLine)
            guard line.range(of: Self.tokenCountNeedle) != nil else { continue }
            guard let event = Self.parseTokenEvent(line) else { continue }
            if let cumulative = event.cumulative {
                defer { previousCumulative = cumulative }
                guard calendar.isDate(event.timestamp, inSameDayAs: date) else { continue }
                totals.add(event.delta ?? cumulative.subtracting(previousCumulative))
            } else if let delta = event.delta, calendar.isDate(event.timestamp, inSameDayAs: date) {
                totals.add(delta)
            }
        }
        return totals
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func relativePath(_ file: URL, from directory: URL) -> String {
        let basePath = directory.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        guard filePath.hasPrefix(basePath) else { return file.lastPathComponent }
        return String(filePath.dropFirst(basePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static let tokenCountNeedle = Data(#""token_count""#.utf8)

    private static func parseTokenEvent(_ data: Data) -> CodexUsageEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "event_msg",
              let timestamp = parseTimestamp(object["timestamp"]),
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any]
        else {
            return nil
        }

        let delta = (info["last_token_usage"] as? [String: Any]).map(CodexUsageTotals.init(raw:))
        let cumulative = (info["total_token_usage"] as? [String: Any]).map(CodexUsageTotals.init(raw:))
        guard delta != nil || cumulative != nil else { return nil }
        return CodexUsageEvent(timestamp: timestamp, delta: delta, cumulative: cumulative)
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date = CodexUsageDateParser.date(from: trimmed, fractionalSeconds: true) {
                return date
            }
            return CodexUsageDateParser.date(from: trimmed, fractionalSeconds: false)
        }
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            let seconds = raw > 1_000_000_000_000 ? raw / 1_000 : raw
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }
}

private struct CodexUsageEvent {
    let timestamp: Date
    let delta: CodexUsageTotals?
    let cumulative: CodexUsageTotals?
}

private struct CodexUsageTotals: Equatable {
    var inputTokens: UInt64 = 0
    var cachedInputTokens: UInt64 = 0
    var outputTokens: UInt64 = 0
    var reasoningOutputTokens: UInt64 = 0
    var totalTokens: UInt64 = 0

    init() {}

    init(raw: [String: Any]) {
        inputTokens = Self.number(raw["input_tokens"])
            ?? Self.number(raw["prompt_tokens"])
            ?? Self.number(raw["input"])
            ?? 0
        cachedInputTokens = Self.number(raw["cached_input_tokens"])
            ?? Self.number(raw["cache_read_input_tokens"])
            ?? Self.number(raw["cached_tokens"])
            ?? 0
        outputTokens = Self.number(raw["output_tokens"])
            ?? Self.number(raw["completion_tokens"])
            ?? Self.number(raw["output"])
            ?? 0
        reasoningOutputTokens = Self.number(raw["reasoning_output_tokens"])
            ?? Self.number(raw["reasoning_tokens"])
            ?? 0
        totalTokens = Self.number(raw["total_tokens"]) ?? (inputTokens + outputTokens + reasoningOutputTokens)
    }

    mutating func add(_ other: CodexUsageTotals) {
        inputTokens += other.inputTokens
        cachedInputTokens += other.cachedInputTokens
        outputTokens += other.outputTokens
        reasoningOutputTokens += other.reasoningOutputTokens
        totalTokens += other.totalTokens
    }

    func subtracting(_ previous: CodexUsageTotals?) -> CodexUsageTotals {
        guard let previous else { return self }
        return CodexUsageTotals(
            inputTokens: inputTokens.saturatingSubtract(previous.inputTokens),
            cachedInputTokens: cachedInputTokens.saturatingSubtract(previous.cachedInputTokens),
            outputTokens: outputTokens.saturatingSubtract(previous.outputTokens),
            reasoningOutputTokens: reasoningOutputTokens.saturatingSubtract(previous.reasoningOutputTokens),
            totalTokens: totalTokens.saturatingSubtract(previous.totalTokens)
        )
    }

    private init(
        inputTokens: UInt64,
        cachedInputTokens: UInt64,
        outputTokens: UInt64,
        reasoningOutputTokens: UInt64,
        totalTokens: UInt64
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }

    private static func number(_ value: Any?) -> UInt64? {
        if let value = value as? UInt64 {
            return value
        }
        if let value = value as? Int, value >= 0 {
            return UInt64(value)
        }
        if let value = value as? NSNumber {
            let raw = value.int64Value
            return raw >= 0 ? UInt64(raw) : nil
        }
        if let value = value as? String {
            return UInt64(value)
        }
        return nil
    }
}

private extension UInt64 {
    func saturatingSubtract(_ other: UInt64) -> UInt64 {
        self > other ? self - other : 0
    }
}

private enum CodexUsageDateParser {
    static func date(from string: String, fractionalSeconds: Bool) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
