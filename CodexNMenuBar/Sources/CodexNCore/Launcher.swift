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
            "--env", "CODEX_ELECTRON_USER_DATA_PATH=\(profile.electronUserData.path)",
            "--args",
            "--user-data-dir=\(profile.electronUserData.path)"
        ]
        if let project {
            arguments.append(project.path)
        }
        return arguments
    }

    public func terminalScript(profile: Profile, cwd: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        [
            "cd \(shellQuote(cwd.path))",
            "export CODEX_HOME=\(shellQuote(profile.codexHome.path))",
            "export CODEX_ELECTRON_USER_DATA_PATH=\(shellQuote(profile.electronUserData.path))",
            "codex"
        ].joined(separator: "; ")
    }

    public func openDesktop(profile: Profile) throws {
        try run("/usr/bin/open", arguments: desktopOpenArguments(profile: profile))
    }

    public func openCLIInTerminal(profile: Profile) throws {
        let script = "tell application \"Terminal\" to do script \(terminalScript(profile: profile).jsonStringLiteral)"
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

private func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

private extension String {
    var jsonStringLiteral: String {
        let data = try! JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8)!
    }
}
