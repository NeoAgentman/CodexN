import Foundation

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
            return URL(filePath: ProfileStoreSupport.expandHome(override))
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
        try secureDirectory(root)
        guard !fileManager.fileExists(atPath: storeURL.path) else {
            try setOwnerOnlyFilePermissions(storeURL)
            return
        }
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
        try ProfileInputValidator.validateProfileID(id)
        if let name {
            try ProfileInputValidator.validateDisplayName(name)
        }
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
        try ProfileInputValidator.validateProfileID(id)
        if let name {
            try ProfileInputValidator.validateDisplayName(name)
        }
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
    public func createAPIKeyProfile(
        id: String,
        name: String? = nil,
        provider: String,
        model: String,
        baseURL: String,
        apiKey: String
    ) throws -> Profile {
        try ProfileInputValidator.validateProfileID(id)
        try ProfileInputValidator.validateProviderID(provider)
        try ProfileInputValidator.validateRequired("model", model)
        try ProfileInputValidator.validateRequired("base URL", baseURL)
        try ProfileInputValidator.validateRequired("API key", apiKey)
        if let name {
            try ProfileInputValidator.validateDisplayName(name)
        }
        try ProfileInputValidator.validateTOMLConfigValue("model", model)
        try ProfileInputValidator.validateTOMLConfigValue("base URL", baseURL)
        try ProfileInputValidator.validateAPIKey(apiKey)
        try ProfileInputValidator.validateBaseURL(baseURL)

        var store = try load()
        if store.profiles.contains(where: { $0.id == id }) {
            throw ProfileStoreError.profileAlreadyExists(id)
        }

        let envName = ProfileStoreSupport.randomAPIKeyEnvName(profileID: id)
        var profile = makeProfile(id: id, name: name ?? id)
        profile.defaultProvider = provider
        profile.apiKeyEnvName = envName
        profile.apiKeyValue = apiKey

        try assertProfileRootAvailable(profile)
        try materialize(profile)
        try CodexConfigWriter.writeAPIKeyConfig(profile: profile, provider: provider, model: model, baseURL: baseURL, envName: envName)
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

    private func load() throws -> Store {
        try ensureStore()
        let data = try Data(contentsOf: storeURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ProfileStoreSupport.parseCodexNDate(value) {
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
        try secureDirectory(root)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ProfileStoreSupport.formatCodexNDate(date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(store)
        try data.write(to: storeURL, options: [.atomic])
        try setOwnerOnlyFilePermissions(storeURL)
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
            apiKeyEnvName: nil,
            apiKeyValue: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private func materialize(_ profile: Profile) throws {
        try secureDirectory(profile.codexHome.deletingLastPathComponent())
        try secureDirectory(profile.codexHome)
        try secureDirectory(profile.electronUserData)
        try secureDirectory(profile.logDir)
    }

    private func assertProfileRootAvailable(_ profile: Profile) throws {
        let profileRoot = profile.codexHome.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: profileRoot.path) else { return }
        let contents = try fileManager.contentsOfDirectory(atPath: profileRoot.path)
        if !contents.isEmpty {
            throw ProfileStoreError.profileDirectoryNotEmpty(profileRoot)
        }
    }

    private func secureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func setOwnerOnlyFilePermissions(_ url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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
