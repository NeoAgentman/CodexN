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

public struct RunningCodexProcessSnapshot: Equatable {
    public let process: FocusedCodexProcessSnapshot
    public let hasVisibleWindow: Bool

    public init(process: FocusedCodexProcessSnapshot, hasVisibleWindow: Bool) {
        self.process = process
        self.hasVisibleWindow = hasVisibleWindow
    }
}

public enum CodexAppActivationPlan: Equatable {
    case launch
    case activate(pid: Int32)
    case reopen(pid: Int32)
}

public enum FocusedCodexProfileResolver {
    public static let profileIDEnvironmentKey = "CODEXN_PROFILE_ID"
    public static let profileIDArgumentName = "--codexn-profile-id"
    public static let fallbackRefreshInterval: TimeInterval = 10

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

    public static func matchingCodexProcessSnapshot(
        for target: FocusedCodexProfileLabel,
        snapshots: [FocusedCodexProcessSnapshot],
        profiles: [Profile]
    ) -> FocusedCodexProcessSnapshot? {
        guard target != .none else { return nil }
        return snapshots.first { resolve(snapshot: $0, profiles: profiles) == target }
    }

    public static func activationPlan(
        for target: FocusedCodexProfileLabel,
        snapshots: [RunningCodexProcessSnapshot],
        profiles: [Profile]
    ) -> CodexAppActivationPlan {
        guard let selected = snapshots.first(where: { resolve(snapshot: $0.process, profiles: profiles) == target }) else {
            return .launch
        }
        return selected.hasVisibleWindow
            ? .activate(pid: selected.process.pid)
            : .reopen(pid: selected.process.pid)
    }

    public static func shouldReadProcessArguments(
        bundleIdentifier: String?,
        localizedName: String?,
        executablePath: String?
    ) -> Bool {
        isCodexApp(
            FocusedCodexProcessSnapshot(
                pid: 0,
                bundleIdentifier: bundleIdentifier,
                localizedName: localizedName,
                executablePath: executablePath,
                arguments: [],
                environment: [:]
            )
        )
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

    public static func menuBarProfileText(for label: FocusedCodexProfileLabel) -> String {
        switch label {
        case .none:
            ""
        case .defaultCodex:
            "Default"
        case .profile(let id):
            id
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
        let name = snapshot.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bundleIdentifier = snapshot.bundleIdentifier?.lowercased()
        let executablePath = snapshot.executablePath.map { normalizedPath($0).lowercased() }
        let isMainName = name == "codex"
        let isMainBundle = bundleIdentifier == "com.openai.codex"
        let isMainExecutable = executablePath?.hasSuffix("/codex.app/contents/macos/codex") == true

        return (isMainBundle && (isMainName || isMainExecutable)) || (isMainName && isMainExecutable)
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
