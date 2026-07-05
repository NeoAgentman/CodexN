import Foundation

public enum FocusedCodexProfileLabel: Equatable {
    case none
    case defaultCodex
    case profile(id: String)
}

public struct FocusedCodexProcessSnapshot: Equatable {
    public let pid: Int32
    public let bundleIdentifier: String?
    public let localizedName: String?
    public let executablePath: String?
    public let arguments: [String]
    public let environment: [String: String]

    public init(
        pid: Int32,
        bundleIdentifier: String?,
        localizedName: String?,
        executablePath: String?,
        arguments: [String],
        environment: [String: String]
    ) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
    }
}

public enum FocusedCodexProfileResolver {
    public static let profileIDEnvironmentKey = "CODEXN_PROFILE_ID"
    public static let profileIDArgumentName = "--codexn-profile-id"

    public static func resolve(snapshot: FocusedCodexProcessSnapshot?, profiles: [Profile]) -> FocusedCodexProfileLabel {
        guard let snapshot, isCodexApp(snapshot) else { return .none }

        if let profileID = explicitProfileIDArgument(snapshot.arguments) {
            return .profile(id: profileID)
        }

        if let profileID = snapshot.environment[profileIDEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !profileID.isEmpty {
            return .profile(id: profileID)
        }

        let candidatePaths = profileCandidatePaths(snapshot: snapshot)
        for profile in profiles {
            if candidatePaths.contains(where: { pathMatches($0, profile.codexHome.path) || pathMatches($0, profile.electronUserData.path) }) {
                return .profile(id: profile.id)
            }
        }

        return .defaultCodex
    }

    public static func menuBarTitle(for label: FocusedCodexProfileLabel) -> String {
        switch label {
        case .none:
            "CodexN"
        case .defaultCodex:
            "CodexN | Default"
        case .profile(let id):
            "CodexN | \(id)"
        }
    }

    public static func menuBarHighlightedSegment(for label: FocusedCodexProfileLabel) -> String? {
        switch label {
        case .none:
            nil
        case .defaultCodex:
            "Default"
        case .profile(let id):
            id
        }
    }

    private static func isCodexApp(_ snapshot: FocusedCodexProcessSnapshot) -> Bool {
        if let name = snapshot.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           name == "codex" || name.hasPrefix("codex ") {
            return true
        }

        if let executablePath = snapshot.executablePath?.lowercased(),
           executablePath.contains("/codex.app/") || executablePath.hasSuffix("/codex.app") {
            return true
        }

        if let bundleIdentifier = snapshot.bundleIdentifier?.lowercased(),
           bundleIdentifier.split(separator: ".").contains("codex") {
            return true
        }

        return false
    }

    private static func profileCandidatePaths(snapshot: FocusedCodexProcessSnapshot) -> [String] {
        var paths: [String] = []
        if let codexHome = snapshot.environment["CODEX_HOME"], !codexHome.isEmpty {
            paths.append(codexHome)
        }
        if let electronUserData = snapshot.environment["CODEX_ELECTRON_USER_DATA_PATH"], !electronUserData.isEmpty {
            paths.append(electronUserData)
        }
        paths.append(contentsOf: userDataDirArguments(snapshot.arguments))
        return paths
    }

    private static func userDataDirArguments(_ arguments: [String]) -> [String] {
        var values: [String] = []
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            if argument == "--user-data-dir", let value = iterator.next(), !value.isEmpty {
                values.append(value)
                continue
            }
            let prefix = "--user-data-dir="
            if argument.hasPrefix(prefix) {
                let value = String(argument.dropFirst(prefix.count))
                if !value.isEmpty {
                    values.append(value)
                }
            }
        }
        return values
    }

    private static func explicitProfileIDArgument(_ arguments: [String]) -> String? {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            if argument == profileIDArgumentName,
               let value = iterator.next()?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
            let prefix = "\(profileIDArgumentName)="
            if argument.hasPrefix(prefix) {
                let value = String(argument.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private static func pathMatches(_ lhs: String, _ rhs: String) -> Bool {
        normalizedPath(lhs) == normalizedPath(rhs)
    }

    private static func normalizedPath(_ path: String) -> String {
        let expanded = path.hasPrefix("~/")
            ? FileManager.default.homeDirectoryForCurrentUser.appending(path: String(path.dropFirst(2))).path
            : path
        return URL(filePath: expanded).standardizedFileURL.path
    }
}
