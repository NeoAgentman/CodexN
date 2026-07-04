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
            "--env", "CODEX_HOME=\(profile.codexHome.path)",
            "--env", "CODEX_ELECTRON_USER_DATA_PATH=\(profile.electronUserData.path)"
        ]
        if let apiKeyEnvironment = apiKeyEnvironment(profile) {
            arguments.append(contentsOf: ["--env", "\(apiKeyEnvironment.name)=\(apiKeyEnvironment.value)"])
        }
        arguments.append(contentsOf: [
            "--args",
            "--user-data-dir=\(profile.electronUserData.path)"
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

    public func terminalScript(profile: Profile, cwd: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        var commands = [
            "cd \(shellQuote(cwd.path))",
            "export CODEX_HOME=\(shellQuote(profile.codexHome.path))",
            "export CODEX_ELECTRON_USER_DATA_PATH=\(shellQuote(profile.electronUserData.path))"
        ]
        if let apiKeyEnvironment = apiKeyEnvironment(profile) {
            commands.append("export \(apiKeyEnvironment.name)=\(shellQuote(apiKeyEnvironment.value))")
        }
        commands.append("codex")
        return commands.joined(separator: "; ")
    }

    public func defaultTerminalScript(cwd: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        [
            "cd \(shellQuote(cwd.path))",
            "codex"
        ].joined(separator: "; ")
    }

    public func openDesktop(profile: Profile) throws {
        try run("/usr/bin/open", arguments: desktopOpenArguments(profile: profile))
    }

    public func openDefaultDesktop() throws {
        try run("/usr/bin/open", arguments: defaultDesktopOpenArguments())
    }

    public func openCLIInTerminal(profile: Profile) throws {
        let script = "tell application \"Terminal\" to do script \(terminalScript(profile: profile).jsonStringLiteral)"
        try run("/usr/bin/osascript", arguments: ["-e", script])
    }

    public func openDefaultCLIInTerminal() throws {
        let script = "tell application \"Terminal\" to do script \(defaultTerminalScript().jsonStringLiteral)"
        try run("/usr/bin/osascript", arguments: ["-e", script])
    }

    private func run(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
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

private func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

private extension String {
    var jsonStringLiteral: String {
        let data = try! JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8)!
    }
}
