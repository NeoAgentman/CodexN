import Foundation

struct CodexUsageFileCollector {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func collectUsageFiles(codexHome: URL, date: Date, calendar: Calendar) -> [URL] {
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
            return collectJSONLFiles(in: codexHome)
        }

        var seenRelativePaths = Set<String>()
        var files: [URL] = []
        for directory in directories {
            for file in collectScopedUsageFiles(in: directory, date: date, calendar: calendar) {
                let key = relativePath(file, from: directory)
                if seenRelativePaths.insert(key).inserted {
                    files.append(file)
                }
            }
        }
        return files
    }

    private func collectScopedUsageFiles(in directory: URL, date: Date, calendar: Calendar) -> [URL] {
        let dayStart = calendar.startOfDay(for: date)
        let scanStart = calendar.date(byAdding: .day, value: -Self.datePartitionPaddingDays, to: dayStart) ?? dayStart
        let scanEnd = calendar.date(byAdding: .day, value: Self.datePartitionPaddingDays, to: dayStart) ?? dayStart
        let recentStart = calendar.date(byAdding: .day, value: -Self.activeSessionLookbackDays, to: dayStart) ?? dayStart
        let modifiedSince = date.addingTimeInterval(-Self.recentModificationLookbackSeconds)

        var seenPaths = Set<String>()
        var files: [URL] = []

        func append(_ candidates: [URL]) {
            for file in candidates where seenPaths.insert(file.path).inserted {
                files.append(file)
            }
        }

        append(collectPartitionedJSONLFiles(in: directory, from: scanStart, through: scanEnd, calendar: calendar))
        append(collectFlatJSONLFiles(in: directory, from: scanStart, through: scanEnd, calendar: calendar))
        append(collectRecentlyModifiedPartitionedJSONLFiles(
            in: directory,
            from: recentStart,
            through: scanEnd,
            modifiedSince: modifiedSince,
            calendar: calendar
        ))
        append(collectRecentlyModifiedFlatJSONLFiles(in: directory, modifiedSince: modifiedSince))

        return files.sorted { $0.path < $1.path }
    }

    private func collectPartitionedJSONLFiles(
        in directory: URL,
        from startDate: Date,
        through endDate: Date,
        calendar: Calendar
    ) -> [URL] {
        var files: [URL] = []
        for day in days(from: startDate, through: endDate, calendar: calendar) {
            let dayDirectory = datePartitionDirectory(in: directory, for: day, calendar: calendar)
            guard isDirectory(dayDirectory) else { continue }
            files.append(contentsOf: collectImmediateJSONLFiles(in: dayDirectory))
        }
        return files
    }

    private func collectFlatJSONLFiles(
        in directory: URL,
        from startDate: Date,
        through endDate: Date,
        calendar: Calendar
    ) -> [URL] {
        let startKey = CodexUsageScanner.dayKey(for: startDate, calendar: calendar)
        let endKey = CodexUsageScanner.dayKey(for: endDate, calendar: calendar)
        return collectImmediateJSONLFiles(in: directory).filter { file in
            guard let dayKey = Self.dayKeyFromFilename(file.lastPathComponent) else { return true }
            return dayKey >= startKey && dayKey <= endKey
        }
    }

    private func collectRecentlyModifiedPartitionedJSONLFiles(
        in directory: URL,
        from startDate: Date,
        through endDate: Date,
        modifiedSince: Date,
        calendar: Calendar
    ) -> [URL] {
        var files: [URL] = []
        for day in days(from: startDate, through: endDate, calendar: calendar) {
            let dayDirectory = datePartitionDirectory(in: directory, for: day, calendar: calendar)
            guard isDirectory(dayDirectory) else { continue }
            files.append(contentsOf: collectImmediateJSONLFiles(in: dayDirectory).filter {
                wasModified($0, atOrAfter: modifiedSince)
            })
        }
        return files
    }

    private func collectRecentlyModifiedFlatJSONLFiles(in directory: URL, modifiedSince: Date) -> [URL] {
        collectImmediateJSONLFiles(in: directory).filter {
            wasModified($0, atOrAfter: modifiedSince)
        }
    }

    private func collectImmediateJSONLFiles(in directory: URL) -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return files.filter { file in
            guard file.pathExtension == "jsonl" else { return false }
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile != false
        }.sorted { $0.path < $1.path }
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

    private func days(from startDate: Date, through endDate: Date, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        while cursor <= end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return days
    }

    private func datePartitionDirectory(in directory: URL, for date: Date, calendar: Calendar) -> URL {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return directory
            .appending(path: String(format: "%04d", components.year ?? 0))
            .appending(path: String(format: "%02d", components.month ?? 0))
            .appending(path: String(format: "%02d", components.day ?? 0))
    }

    private func wasModified(_ file: URL, atOrAfter cutoff: Date) -> Bool {
        let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
        guard values?.isRegularFile != false else { return false }
        guard let modifiedAt = values?.contentModificationDate else { return false }
        return modifiedAt >= cutoff
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

    private static func dayKeyFromFilename(_ filename: String) -> String? {
        let pattern = #"\d{4}-\d{2}-\d{2}"#
        guard let range = filename.range(of: pattern, options: .regularExpression) else { return nil }
        return String(filename[range])
    }

    private static let datePartitionPaddingDays = 1
    private static let activeSessionLookbackDays = 30
    private static let recentModificationLookbackSeconds: TimeInterval = 48 * 60 * 60
}
