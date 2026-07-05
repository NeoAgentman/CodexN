import Foundation

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
        let collector = CodexUsageFileCollector(fileManager: fileManager)
        let logScanner = CodexUsageLogScanner()
        var totals = CodexUsageTotals()
        for file in collector.collectUsageFiles(codexHome: profile.codexHome, date: date, calendar: calendar) {
            totals.add(try logScanner.scanUsageFile(file, date: date, calendar: calendar))
        }
        return totals
    }
}
