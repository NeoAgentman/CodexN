import Foundation

public struct Profile: Codable, Equatable, Identifiable {
    public let id: String
    public var name: String
    public var codexHome: URL
    public var electronUserData: URL
    public var logDir: URL
    public var appBundle: URL
    public var defaultProvider: String
    public var createdAt: Date
    public var updatedAt: Date
}

public enum ProfileStoreError: Error, CustomStringConvertible {
    case invalidProfileID(String)
    case profileAlreadyExists(String)
    case profileNotFound(String)
    case profileDirectoryNotEmpty(URL)
    case missingSourceDirectory(URL)
    case processFailed(String, Int32)

    public var description: String {
        switch self {
        case .invalidProfileID(let id):
            return "Invalid profile id: \(id)"
        case .profileAlreadyExists(let id):
            return "Profile already exists: \(id)"
        case .profileNotFound(let id):
            return "Profile not found: \(id)"
        case .profileDirectoryNotEmpty(let url):
            return "Profile directory is not empty: \(url.path)"
        case .missingSourceDirectory(let url):
            return "Source directory does not exist: \(url.path)"
        case .processFailed(let command, let code):
            return "\(command) exited with code \(code)"
        }
    }
}

public final class ProfileStore {
    private struct Store: Codable {
        var version: Int
        var profiles: [Profile]
    }

    public let root: URL
    private let fileManager: FileManager
    private let storeURL: URL

    public init(root: URL = ProfileStore.defaultRoot(), fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
        self.storeURL = root.appending(path: "profiles.json")
    }

    public static func defaultRoot(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["CODEXN_ROOT"], !override.isEmpty {
            return URL(filePath: expandHome(override))
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex-profiles")
    }

    public static func defaultCodexHome() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex")
    }

    public static func defaultElectronUserData() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Codex")
    }

    public func ensureStore() throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: storeURL.path) else { return }
        try save(Store(version: 1, profiles: []))
    }

    public func listProfiles() throws -> [Profile] {
        try load().profiles.sorted { $0.id < $1.id }
    }

    public func getProfile(id: String) throws -> Profile {
        guard let profile = try load().profiles.first(where: { $0.id == id }) else {
            throw ProfileStoreError.profileNotFound(id)
        }
        return profile
    }

    @discardableResult
    public func createProfile(id: String, name: String? = nil) throws -> Profile {
        try validateProfileID(id)
        var store = try load()
        if store.profiles.contains(where: { $0.id == id }) {
            throw ProfileStoreError.profileAlreadyExists(id)
        }
        let profile = makeProfile(id: id, name: name ?? id)
        try assertProfileRootAvailable(profile)
        try materialize(profile)
        store.profiles.append(profile)
        try save(store)
        return profile
    }

    @discardableResult
    public func importDefaultProfile(
        id: String,
        name: String? = nil,
        defaultCodexHome: URL = ProfileStore.defaultCodexHome(),
        defaultElectronUserData: URL = ProfileStore.defaultElectronUserData()
    ) throws -> Profile {
        try validateProfileID(id)
        var store = try load()
        if store.profiles.contains(where: { $0.id == id }) {
            throw ProfileStoreError.profileAlreadyExists(id)
        }
        guard fileManager.fileExists(atPath: defaultCodexHome.path) else {
            throw ProfileStoreError.missingSourceDirectory(defaultCodexHome)
        }
        guard fileManager.fileExists(atPath: defaultElectronUserData.path) else {
            throw ProfileStoreError.missingSourceDirectory(defaultElectronUserData)
        }

        let profile = makeProfile(id: id, name: name ?? id)
        try assertProfileRootAvailable(profile)
        try materialize(profile)
        try runDitto(arguments: [defaultCodexHome.path, profile.codexHome.path])
        try runDitto(arguments: [defaultElectronUserData.path, profile.electronUserData.path])
        store.profiles.append(profile)
        try save(store)
        return profile
    }

    @discardableResult
    public func deleteProfile(id: String) throws -> Profile {
        var store = try load()
        guard let index = store.profiles.firstIndex(where: { $0.id == id }) else {
            throw ProfileStoreError.profileNotFound(id)
        }
        let profile = store.profiles.remove(at: index)
        try save(store)
        return profile
    }

    public func backupProfile(id: String) throws -> URL {
        let profile = try getProfile(id: id)
        let profileRoot = profile.codexHome.deletingLastPathComponent()
        let backupRoot = root.appending(path: "backups")
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        let target = backupRoot.appending(path: "\(id)-\(timestamp()).zip")
        try runDitto(arguments: [
            "-c", "-k", "--sequesterRsrc", "--keepParent",
            profileRoot.path,
            target.path
        ])
        return target
    }

    private func load() throws -> Store {
        try ensureStore()
        let data = try Data(contentsOf: storeURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = parseCodexNDate(value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected CodexN ISO8601 date string."
            )
        }
        return try decoder.decode(Store.self, from: data)
    }

    private func save(_ store: Store) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatCodexNDate(date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(store)
        try data.write(to: storeURL)
    }

    private func makeProfile(id: String, name: String) -> Profile {
        let now = Date()
        let profileRoot = root.appending(path: id)
        return Profile(
            id: id,
            name: name,
            codexHome: profileRoot.appending(path: "codex-home"),
            electronUserData: profileRoot.appending(path: "electron-user-data"),
            logDir: profileRoot.appending(path: "logs"),
            appBundle: URL(filePath: "/Applications/Codex.app"),
            defaultProvider: "openai",
            createdAt: now,
            updatedAt: now
        )
    }

    private func materialize(_ profile: Profile) throws {
        try fileManager.createDirectory(at: profile.codexHome, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: profile.electronUserData, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: profile.logDir, withIntermediateDirectories: true)
    }

    private func assertProfileRootAvailable(_ profile: Profile) throws {
        let profileRoot = profile.codexHome.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: profileRoot.path) else { return }
        let contents = try fileManager.contentsOfDirectory(atPath: profileRoot.path)
        if !contents.isEmpty {
            throw ProfileStoreError.profileDirectoryNotEmpty(profileRoot)
        }
    }

    private func validateProfileID(_ id: String) throws {
        let pattern = #"^[A-Za-z0-9._-]+$"#
        if id.range(of: pattern, options: .regularExpression) == nil {
            throw ProfileStoreError.invalidProfileID(id)
        }
    }

    private func runDitto(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw ProfileStoreError.processFailed("ditto", process.terminationStatus)
        }
    }
}

private func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
}

private func parseCodexNDate(_ value: String) -> Date? {
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    fractionalFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    if let date = fractionalFormatter.date(from: value) {
        return date
    }

    let plainFormatter = ISO8601DateFormatter()
    plainFormatter.formatOptions = [.withInternetDateTime]
    plainFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    return plainFormatter.date(from: value)
}

private func formatCodexNDate(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
}

private func expandHome(_ value: String) -> String {
    if value == "~" {
        return FileManager.default.homeDirectoryForCurrentUser.path
    }
    if value.hasPrefix("~/") {
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: String(value.dropFirst(2)))
            .path
    }
    return value
}
