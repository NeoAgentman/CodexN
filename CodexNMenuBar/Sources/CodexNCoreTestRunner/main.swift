import Foundation
import CodexNCore

@main
struct TestRunner {
    static func main() throws {
        try createsEmptyProfileDirectoriesWithoutCodexConfig()
        try refusesToCreateOverNonEmptyProfileDirectory()
        try importsDefaultCodexHomeAndElectronData()
        try createsAPIKeyProfileWithoutLeakingKeyToConfig()
        try rejectsInvalidAPIKeyProviderID()
        try buildsLaunchCommandsWithProfileIsolation()
        try injectsAPIKeyEnvironmentIntoLaunchCommands()
        try buildsTerminalAppleScriptWithoutInvalidSlashEscapes()
        try readsLegacyProfileRegistry()
        try buildsDefaultLaunchCommandsWithoutProfileIsolation()
        print("CodexNCoreTestRunner: all tests passed")
    }

    private static func createsEmptyProfileDirectoriesWithoutCodexConfig() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)

        let profile = try store.createProfile(id: "work", name: "Work")

        try expect(profile.id == "work", "profile id should be work")
        try expect(profile.codexHome.path.hasPrefix(root.path), "codexHome should be under root")
        try expect(FileManager.default.fileExists(atPath: profile.codexHome.path), "codexHome should exist")
        try expect(FileManager.default.fileExists(atPath: profile.electronUserData.path), "electronUserData should exist")
        try expect(FileManager.default.fileExists(atPath: profile.logDir.path), "logDir should exist")
        try expect(
            !FileManager.default.fileExists(atPath: profile.codexHome.appending(path: "config.toml").path),
            "config.toml should not be created by init"
        )
        try expect(try store.listProfiles().map(\.id) == ["work"], "store should list work")
    }

    private static func refusesToCreateOverNonEmptyProfileDirectory() throws {
        let root = try temporaryDirectory()
        let staleHome = root.appending(path: "work/codex-home")
        try FileManager.default.createDirectory(at: staleHome, withIntermediateDirectories: true)
        try "model_provider = \"openai\"\n".write(
            to: staleHome.appending(path: "config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let store = ProfileStore(root: root)

        do {
            _ = try store.createProfile(id: "work", name: "Work")
            throw TestFailure("createProfile should reject a non-empty profile directory")
        } catch {
            try expect(String(describing: error).contains("Profile directory is not empty"), "wrong error: \(error)")
        }
    }

    private static func importsDefaultCodexHomeAndElectronData() throws {
        let root = try temporaryDirectory()
        let source = try temporaryDirectory()
        let codexHome = source.appending(path: ".codex")
        let electronUserData = source.appending(path: "Library/Application Support/Codex")
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: electronUserData, withIntermediateDirectories: true)
        try "model_provider = \"openai\"\n".write(
            to: codexHome.appending(path: "config.toml"),
            atomically: true,
            encoding: .utf8
        )
        try "{\"ok\":true}\n".write(
            to: electronUserData.appending(path: "Preferences"),
            atomically: true,
            encoding: .utf8
        )

        let store = ProfileStore(root: root)
        let profile = try store.importDefaultProfile(
            id: "default-copy",
            name: "Default Copy",
            defaultCodexHome: codexHome,
            defaultElectronUserData: electronUserData
        )

        try expect(
            try String(contentsOf: profile.codexHome.appending(path: "config.toml"), encoding: .utf8) == "model_provider = \"openai\"\n",
            "codex config should be copied"
        )
        try expect(
            try String(contentsOf: profile.electronUserData.appending(path: "Preferences"), encoding: .utf8) == "{\"ok\":true}\n",
            "electron Preferences should be copied"
        )
        try expect(try store.listProfiles().map(\.id) == ["default-copy"], "store should list imported profile")
    }

    private static func createsAPIKeyProfileWithoutLeakingKeyToConfig() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)

        let profile = try store.createAPIKeyProfile(
            id: "zl",
            name: "ZL",
            provider: "zl",
            model: "gpt-5.5",
            baseURL: "https://api.agpt.uk/v1",
            apiKey: "sk-test-secret"
        )

        let config = try String(contentsOf: profile.codexHome.appending(path: "config.toml"), encoding: .utf8)
        try expect(config.contains("model = \"gpt-5.5\""), "config should include model")
        try expect(config.contains("model_provider = \"zl\""), "config should include provider")
        try expect(config.contains("base_url = \"https://api.agpt.uk/v1\""), "config should include base URL")
        try expect(config.contains("wire_api = \"responses\""), "config should include responses wire API")
        try expect(!config.contains("sk-test-secret"), "config.toml should not contain the API key")

        let loaded = try store.getProfile(id: "zl")
        try expect(loaded.apiKeyEnvName?.hasPrefix("CODEXN_API_KEY_ZL_") == true, "profile should store generated env name")
        try expect(loaded.apiKeyValue == "sk-test-secret", "profile registry should store API key value for v1")
        try expect(config.contains("env_key = \"\(loaded.apiKeyEnvName!)\""), "config should point to generated env name")
    }

    private static func rejectsInvalidAPIKeyProviderID() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)

        do {
            _ = try store.createAPIKeyProfile(
                id: "bad",
                provider: "bad provider",
                model: "gpt-5.5",
                baseURL: "https://example.test/v1",
                apiKey: "secret"
            )
            throw TestFailure("createAPIKeyProfile should reject invalid provider ids")
        } catch {
            try expect(String(describing: error).contains("Invalid provider id"), "wrong error: \(error)")
        }
    }

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "codexn-menubar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func buildsLaunchCommandsWithProfileIsolation() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)
        let profile = try store.createProfile(id: "work", name: "Work")
        let launcher = Launcher()

        let desktopArguments = launcher.desktopOpenArguments(profile: profile)
        try expect(desktopArguments.contains("CODEX_HOME=\(profile.codexHome.path)"), "desktop args should include CODEX_HOME")
        try expect(
            desktopArguments.contains("CODEX_ELECTRON_USER_DATA_PATH=\(profile.electronUserData.path)"),
            "desktop args should include CODEX_ELECTRON_USER_DATA_PATH"
        )
        try expect(
            desktopArguments.contains("--user-data-dir=\(profile.electronUserData.path)"),
            "desktop args should include chromium user data dir"
        )

        let terminalScript = launcher.terminalScript(profile: profile)
        try expect(terminalScript.contains("export CODEX_HOME="), "terminal script should export CODEX_HOME")
        try expect(terminalScript.contains("export CODEX_ELECTRON_USER_DATA_PATH="), "terminal script should export electron user data")
        try expect(terminalScript.hasSuffix("; codex"), "terminal script should run codex")
    }

    private static func injectsAPIKeyEnvironmentIntoLaunchCommands() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)
        let profile = try store.createAPIKeyProfile(
            id: "api",
            provider: "zl",
            model: "gpt-5.5",
            baseURL: "https://api.example.test/v1",
            apiKey: "sk-test secret"
        )
        let launcher = Launcher()
        let envName = try require(profile.apiKeyEnvName, "API key env name should exist")

        let desktopArguments = launcher.desktopOpenArguments(profile: profile)
        try expect(
            desktopArguments.contains("\(envName)=sk-test secret"),
            "desktop args should include API key env"
        )
        try expect(
            desktopArguments.firstIndex(of: "\(envName)=sk-test secret")! < desktopArguments.firstIndex(of: "--args")!,
            "desktop API key env should appear before --args"
        )

        let terminalScript = launcher.terminalScript(profile: profile)
        try expect(
            terminalScript.contains("export \(envName)='sk-test secret'"),
            "terminal script should export API key env"
        )
    }

    private static func buildsTerminalAppleScriptWithoutInvalidSlashEscapes() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)
        let profile = try store.createProfile(id: "work", name: "Work")
        let launcher = Launcher()

        let appleScript = launcher.terminalAppleScript(profile: profile)

        try expect(appleScript.contains("tell application \"Terminal\" to do script"), "should target Terminal")
        try expect(!appleScript.contains("\\/"), "AppleScript should not use JSON-style slash escapes")
        try expect(appleScript.contains("/codex-home"), "AppleScript should include the profile codex home path")
    }

    private static func readsLegacyProfileRegistry() throws {
        let root = try temporaryDirectory()
        let json = """
        {
          "version": 1,
          "profiles": [
            {
              "id": "zl",
              "name": "zl",
              "codexHome": "\(root.path)/zl/codex-home",
              "electronUserData": "\(root.path)/zl/electron-user-data",
              "logDir": "\(root.path)/zl/logs",
              "appBundle": "/Applications/Codex.app",
              "defaultProvider": "openai",
              "createdAt": "2026-07-04T05:54:08.746Z",
              "updatedAt": "2026-07-04T05:54:08.751Z"
            }
          ]
        }
        """
        try json.write(to: root.appending(path: "profiles.json"), atomically: true, encoding: .utf8)

        let store = ProfileStore(root: root)
        let profiles = try store.listProfiles()

        try expect(profiles.map(\.id) == ["zl"], "should decode legacy registry timestamps")
    }

    private static func buildsDefaultLaunchCommandsWithoutProfileIsolation() throws {
        let launcher = Launcher()
        let desktopArguments = launcher.defaultDesktopOpenArguments()

        try expect(desktopArguments == ["-n", "/Applications/Codex.app"], "default desktop should not include profile env")
        try expect(!desktopArguments.contains(where: { $0.contains("CODEX_HOME") }), "default desktop should not include CODEX_HOME")
        try expect(!desktopArguments.contains(where: { $0.contains("user-data-dir") }), "default desktop should not include user-data-dir")

        let terminalScript = launcher.defaultTerminalScript(cwd: URL(filePath: "/tmp"))
        try expect(terminalScript == "cd '/tmp'; codex", "default CLI should run codex without profile env")
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() {
            throw TestFailure(message)
        }
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw TestFailure(message)
        }
        return value
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
