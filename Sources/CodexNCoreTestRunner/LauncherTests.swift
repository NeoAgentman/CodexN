import Foundation
import CodexNCore

extension TestRunner {
    static func buildsLaunchCommandsWithProfileIsolation() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)
        let profile = try store.createProfile(id: "work", name: "Work")
        let launcher = Launcher()

        let desktopArguments = launcher.desktopOpenArguments(profile: profile)
        try expect(
            desktopArguments.contains("CODEXN_PROFILE_ID=work"),
            "desktop args should include explicit CodexN profile id"
        )
        try expect(
            desktopArguments.contains("--codexn-profile-id=work"),
            "desktop args should include explicit CodexN profile id argument"
        )
        try expect(desktopArguments.contains("CODEX_HOME=\(profile.codexHome.path)"), "desktop args should include CODEX_HOME")
        try expect(
            desktopArguments.contains("CODEX_ELECTRON_USER_DATA_PATH=\(profile.electronUserData.path)"),
            "desktop args should include CODEX_ELECTRON_USER_DATA_PATH"
        )
        try expect(
            desktopArguments.contains("--user-data-dir=\(profile.electronUserData.path)"),
            "desktop args should include chromium user data dir"
        )
    }

    static func injectsAPIKeyEnvironmentIntoLaunchCommands() throws {
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
    }

    static func readsLegacyProfileRegistry() throws {
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

    static func buildsDefaultLaunchCommandsWithoutProfileIsolation() throws {
        let launcher = Launcher()
        let desktopArguments = launcher.defaultDesktopOpenArguments()

        try expect(desktopArguments == ["-n", "/Applications/Codex.app"], "default desktop should not include profile env")
        try expect(!desktopArguments.contains(where: { $0.contains("CODEX_HOME") }), "default desktop should not include CODEX_HOME")
        try expect(!desktopArguments.contains(where: { $0.contains("user-data-dir") }), "default desktop should not include user-data-dir")
    }

    static func stripsCodexEnvironmentWhenLaunchingDefaultApp() throws {
        let launcher = Launcher()
        let environment = launcher.defaultDesktopLaunchEnvironment(environment: [
            "HOME": "/Users/example",
            "PATH": "/usr/bin:/bin",
            "CODEX_HOME": "/tmp/profile/codex-home",
            "CODEX_ELECTRON_USER_DATA_PATH": "/tmp/profile/electron-user-data",
            "CODEX_INTERNAL_ORIGINATOR_OVERRIDE": "Codex Desktop",
            "CODEXN_API_KEY_ZL_ABC": "secret",
            "CODEXN_ROOT": "/tmp/profiles"
        ])

        try expect(environment["HOME"] == "/Users/example", "default launch should preserve unrelated environment")
        try expect(environment["PATH"] == "/usr/bin:/bin", "default launch should preserve PATH")
        try expect(environment["CODEX_HOME"] == nil, "default launch should remove CODEX_HOME")
        try expect(environment["CODEX_ELECTRON_USER_DATA_PATH"] == nil, "default launch should remove electron user data")
        try expect(environment["CODEX_INTERNAL_ORIGINATOR_OVERRIDE"] == nil, "default launch should remove Codex internal env")
        try expect(environment["CODEXN_API_KEY_ZL_ABC"] == nil, "default launch should remove CodexN API key env")
        try expect(environment["CODEXN_ROOT"] == nil, "default launch should remove CodexN root env")
    }
}
