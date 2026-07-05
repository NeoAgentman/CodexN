import Foundation

public enum LauncherError: Error, CustomStringConvertible {
    case processFailed(String, Int32)

    public var description: String {
        switch self {
        case .processFailed(let command, let code):
            return "\(command) exited with code \(code)"
        }
    }
}

public struct Launcher {
    public init() {}

    public func desktopOpenArguments(profile: Profile, project: URL? = nil, app: URL? = nil) -> [String] {
        let appURL = app ?? profile.appBundle
        var arguments = [
            "-n",
            appURL.path,
            "--env", "\(FocusedCodexProfileResolver.profileIDEnvironmentKey)=\(profile.id)",
            "--env", "CODEX_HOME=\(profile.codexHome.path)",
            "--env", "CODEX_ELECTRON_USER_DATA_PATH=\(profile.electronUserData.path)"
        ]
        if let apiKeyEnvironment = apiKeyEnvironment(profile) {
            arguments.append(contentsOf: ["--env", "\(apiKeyEnvironment.name)=\(apiKeyEnvironment.value)"])
        }
        arguments.append(contentsOf: [
            "--args",
            "--user-data-dir=\(profile.electronUserData.path)",
            "\(FocusedCodexProfileResolver.profileIDArgumentName)=\(profile.id)"
        ])
        if let project {
            arguments.append(project.path)
        }
        return arguments
    }

    public func defaultDesktopOpenArguments(project: URL? = nil, app: URL = URL(filePath: "/Applications/Codex.app")) -> [String] {
        var arguments = ["-n", app.path]
        if let project {
            arguments.append(contentsOf: ["--args", project.path])
        }
        return arguments
    }

    public func defaultDesktopLaunchEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        environment.filter { key, _ in
            !key.hasPrefix("CODEX_") && !key.hasPrefix("CODEXN_")
        }
    }

    public func openDesktop(profile: Profile) throws {
        try run("/usr/bin/open", arguments: desktopOpenArguments(profile: profile))
    }

    public func openDefaultDesktop() throws {
        try run(
            "/usr/bin/open",
            arguments: defaultDesktopOpenArguments(),
            environment: defaultDesktopLaunchEnvironment()
        )
    }

    private func run(_ executable: String, arguments: [String], environment: [String: String]? = nil) throws {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw LauncherError.processFailed(executable, process.terminationStatus)
        }
    }
}

private func apiKeyEnvironment(_ profile: Profile) -> (name: String, value: String)? {
    guard let name = profile.apiKeyEnvName, !name.isEmpty else { return nil }
    guard let value = profile.apiKeyValue, !value.isEmpty else { return nil }
    return (name, value)
}
