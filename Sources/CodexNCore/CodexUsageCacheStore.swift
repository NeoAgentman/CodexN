import Foundation

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
