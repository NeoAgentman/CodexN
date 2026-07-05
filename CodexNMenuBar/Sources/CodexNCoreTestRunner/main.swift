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
        try readsLegacyProfileRegistry()
        try buildsDefaultLaunchCommandsWithoutProfileIsolation()
        try stripsCodexEnvironmentWhenLaunchingDefaultApp()
        try resolvesFocusedManagedProfileFromExplicitProfileEnvironment()
        try resolvesFocusedManagedProfileFromExplicitProfileArgument()
        try resolvesFocusedManagedProfileFromCodexHomeEnvironment()
        try resolvesFocusedManagedProfileFromElectronUserDataEnvironment()
        try resolvesFocusedManagedProfileFromUserDataDirArgument()
        try resolvesDefaultCodexForCodexAppWithoutProfileMatch()
        try ignoresNonCodexForegroundApps()
        try formatsFocusedProfileMenuTitles()
        try identifiesFocusedProfileTitleHighlightSegment()
        try skipsProcessArgumentReadsForNonCodexApps()
        try usesTenSecondFocusedProfileFallbackInterval()
        try parsesKernelProcessArgumentsAndEnvironment()
        try scansTodayUsageFromCodexHomes()
        try scansRecentlyModifiedOlderCodexSessionPartitionsOnly()
        try writesAndReadsUsageCache()
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
    }

    private static func stripsCodexEnvironmentWhenLaunchingDefaultApp() throws {
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

    private static func resolvesFocusedManagedProfileFromExplicitProfileEnvironment() throws {
        let snapshot = codexProcessSnapshot(environment: ["CODEXN_PROFILE_ID": "work"])

        let label = FocusedCodexProfileResolver.resolve(snapshot: snapshot, profiles: [])

        try expect(label == .profile(id: "work"), "explicit CodexN profile id should identify the focused profile")
    }

    private static func resolvesFocusedManagedProfileFromExplicitProfileArgument() throws {
        let snapshot = codexProcessSnapshot(arguments: ["--codexn-profile-id=work"])

        let label = FocusedCodexProfileResolver.resolve(snapshot: snapshot, profiles: [])

        try expect(label == .profile(id: "work"), "explicit CodexN profile id argument should identify the focused profile")
    }

    private static func resolvesFocusedManagedProfileFromCodexHomeEnvironment() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)
        let profile = try store.createProfile(id: "work", name: "Work")
        let snapshot = codexProcessSnapshot(environment: ["CODEX_HOME": profile.codexHome.path])

        let label = FocusedCodexProfileResolver.resolve(snapshot: snapshot, profiles: [profile])

        try expect(label == .profile(id: "work"), "CODEX_HOME should identify the focused profile")
    }

    private static func resolvesFocusedManagedProfileFromElectronUserDataEnvironment() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)
        let profile = try store.createProfile(id: "personal", name: "Personal")
        let snapshot = codexProcessSnapshot(environment: ["CODEX_ELECTRON_USER_DATA_PATH": profile.electronUserData.path])

        let label = FocusedCodexProfileResolver.resolve(snapshot: snapshot, profiles: [profile])

        try expect(label == .profile(id: "personal"), "CODEX_ELECTRON_USER_DATA_PATH should identify the focused profile")
    }

    private static func resolvesFocusedManagedProfileFromUserDataDirArgument() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)
        let profile = try store.createProfile(id: "zl", name: "ZL")
        let snapshot = codexProcessSnapshot(arguments: ["--user-data-dir=\(profile.electronUserData.path)"])

        let label = FocusedCodexProfileResolver.resolve(snapshot: snapshot, profiles: [profile])

        try expect(label == .profile(id: "zl"), "--user-data-dir should identify the focused profile")
    }

    private static func resolvesDefaultCodexForCodexAppWithoutProfileMatch() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)
        let profile = try store.createProfile(id: "work", name: "Work")
        let snapshot = codexProcessSnapshot(arguments: ["--user-data-dir=/tmp/elsewhere"])

        let label = FocusedCodexProfileResolver.resolve(snapshot: snapshot, profiles: [profile])

        try expect(label == .defaultCodex, "unmatched Codex app should be treated as Default")
    }

    private static func ignoresNonCodexForegroundApps() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)
        let profile = try store.createProfile(id: "work", name: "Work")
        let snapshot = FocusedCodexProcessSnapshot(
            pid: 42,
            bundleIdentifier: "com.apple.Terminal",
            localizedName: "Terminal",
            executablePath: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal",
            arguments: ["zsh"],
            environment: ["CODEX_HOME": profile.codexHome.path]
        )

        let label = FocusedCodexProfileResolver.resolve(snapshot: snapshot, profiles: [profile])

        try expect(label == .none, "non-Codex apps should not update the menu bar profile label")
    }

    private static func formatsFocusedProfileMenuTitles() throws {
        try expect(FocusedCodexProfileResolver.menuBarTitle(for: .none) == "CodexN", "none title should be plain")
        try expect(FocusedCodexProfileResolver.menuBarTitle(for: .defaultCodex) == "CodexN | Default", "default title should be labeled")
        try expect(FocusedCodexProfileResolver.menuBarTitle(for: .profile(id: "work")) == "CodexN | work", "profile title should include id")
    }

    private static func identifiesFocusedProfileTitleHighlightSegment() throws {
        try expect(FocusedCodexProfileResolver.menuBarHighlightedSegment(for: .none) == nil, "plain title should not have highlighted text")
        try expect(FocusedCodexProfileResolver.menuBarHighlightedSegment(for: .defaultCodex) == "Default", "default title should highlight Default")
        try expect(FocusedCodexProfileResolver.menuBarHighlightedSegment(for: .profile(id: "work")) == "work", "profile title should highlight profile id")
    }

    private static func skipsProcessArgumentReadsForNonCodexApps() throws {
        try expect(
            !FocusedCodexProfileResolver.shouldReadProcessArguments(
                bundleIdentifier: "com.apple.Terminal",
                localizedName: "Terminal",
                executablePath: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"
            ),
            "non-Codex apps should not require process argument reads"
        )
        try expect(
            FocusedCodexProfileResolver.shouldReadProcessArguments(
                bundleIdentifier: "com.openai.codex",
                localizedName: "Codex",
                executablePath: "/Applications/Codex.app/Contents/MacOS/Codex"
            ),
            "Codex apps should require process argument reads"
        )
    }

    private static func usesTenSecondFocusedProfileFallbackInterval() throws {
        try expect(
            FocusedCodexProfileResolver.fallbackRefreshInterval == 10,
            "focused profile fallback polling interval should be 10 seconds"
        )
    }

    private static func parsesKernelProcessArgumentsAndEnvironment() throws {
        let data = kernelProcessArgumentsData(
            executablePath: "/Applications/Codex.app/Contents/MacOS/Codex",
            arguments: [
                "/Applications/Codex.app/Contents/MacOS/Codex",
                "--user-data-dir=/Users/example/Library/Application Support/CodexN/work"
            ],
            environment: [
                "CODEX_HOME=/Users/example/.codex-profiles/work/codex-home",
                "CODEX_ELECTRON_USER_DATA_PATH=/Users/example/Library/Application Support/CodexN/work"
            ]
        )

        let parsed = FocusedCodexProcessArgumentsParser.parse(data)

        try expect(
            parsed.arguments.contains("--user-data-dir=/Users/example/Library/Application Support/CodexN/work"),
            "parser should preserve spaces inside arguments"
        )
        try expect(
            parsed.environment["CODEX_HOME"] == "/Users/example/.codex-profiles/work/codex-home",
            "parser should decode CODEX_HOME"
        )
        try expect(
            parsed.environment["CODEX_ELECTRON_USER_DATA_PATH"] == "/Users/example/Library/Application Support/CodexN/work",
            "parser should decode electron user data path"
        )
    }

    private static func codexProcessSnapshot(
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) -> FocusedCodexProcessSnapshot {
        FocusedCodexProcessSnapshot(
            pid: 42,
            bundleIdentifier: "com.openai.codex",
            localizedName: "Codex",
            executablePath: "/Applications/Codex.app/Contents/MacOS/Codex",
            arguments: arguments,
            environment: environment
        )
    }

    private static func kernelProcessArgumentsData(
        executablePath: String,
        arguments: [String],
        environment: [String]
    ) -> Data {
        var data = Data()
        var argc = Int32(arguments.count)
        withUnsafeBytes(of: &argc) { data.append(contentsOf: $0) }
        appendNullTerminated(executablePath, to: &data)
        data.append(0)
        arguments.forEach { appendNullTerminated($0, to: &data) }
        environment.forEach { appendNullTerminated($0, to: &data) }
        data.append(0)
        return data
    }

    private static func appendNullTerminated(_ value: String, to data: inout Data) {
        data.append(value.data(using: .utf8)!)
        data.append(0)
    }

    private static func scansTodayUsageFromCodexHomes() throws {
        let root = try temporaryDirectory()
        let codexHome = root.appending(path: "work/codex-home")
        let sessions = codexHome.appending(path: "sessions")
        let archived = codexHome.appending(path: "archived_sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 12))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        try [
            tokenLine(timestamp: yesterday, total: usage(input: 80, cached: 10, output: 20, total: 100)),
            tokenLine(timestamp: today, total: usage(input: 130, cached: 20, output: 30, total: 160)),
            tokenLine(timestamp: today, last: usage(input: 7, cached: 2, output: 3, total: 10), total: usage(input: 137, cached: 22, output: 33, total: 170))
        ].joined(separator: "\n").write(
            to: sessions.appending(path: "session.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try tokenLine(timestamp: today, last: usage(input: 4, cached: 1, output: 5, total: 9))
            .write(to: archived.appending(path: "archived-only.jsonl"), atomically: true, encoding: .utf8)
        try tokenLine(timestamp: today, last: usage(input: 999, cached: 0, output: 1, total: 1_000))
            .write(to: archived.appending(path: "session.jsonl"), atomically: true, encoding: .utf8)

        let scanner = CodexUsageScanner()
        let snapshot = try scanner.scanToday(
            profiles: [CodexUsageProfile(id: "work", name: "Work", codexHome: codexHome)],
            date: today,
            calendar: calendar
        )

        try expect(snapshot.dayKey == "2027-01-01", "snapshot should use local day key")
        try expect(snapshot.totalTokens == 79, "today total should add cumulative delta, last usage, and archived-only usage")
        try expect(snapshot.profiles.count == 1, "should include one profile")
        try expect(snapshot.profiles[0].totalTokens == 79, "profile total should be 79")
        try expect(snapshot.profiles[0].cachedInputTokens == 13, "cached input should add delta and last usage")
    }

    private static func scansRecentlyModifiedOlderCodexSessionPartitionsOnly() throws {
        let root = try temporaryDirectory()
        let codexHome = root.appending(path: "work/codex-home")
        let sessions = codexHome.appending(path: "sessions")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2027, month: 3, day: 11, hour: 12))!
        let recentlyModified = calendar.date(byAdding: .hour, value: -12, to: today)!
        let staleModified = calendar.date(byAdding: .day, value: -10, to: today)!

        let activeOldPartition = sessions.appending(path: "2027/03/01")
        let staleOldPartition = sessions.appending(path: "2027/03/02")
        try FileManager.default.createDirectory(at: activeOldPartition, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staleOldPartition, withIntermediateDirectories: true)

        let activeFile = activeOldPartition.appending(path: "rollout-2027-03-01T09-00-00-active.jsonl")
        let staleFile = staleOldPartition.appending(path: "rollout-2027-03-02T09-00-00-stale.jsonl")
        try tokenLine(timestamp: today, last: usage(input: 11, cached: 2, output: 3, total: 14))
            .write(to: activeFile, atomically: true, encoding: .utf8)
        try tokenLine(timestamp: today, last: usage(input: 999, cached: 0, output: 1, total: 1_000))
            .write(to: staleFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: recentlyModified], ofItemAtPath: activeFile.path)
        try FileManager.default.setAttributes([.modificationDate: staleModified], ofItemAtPath: staleFile.path)

        let scanner = CodexUsageScanner()
        let snapshot = try scanner.scanToday(
            profiles: [CodexUsageProfile(id: "work", name: "Work", codexHome: codexHome)],
            date: today,
            calendar: calendar
        )

        try expect(snapshot.totalTokens == 14, "recently modified older partitions should be scanned without full recursion")
        try expect(snapshot.profiles[0].inputTokens == 11, "stale older partitions should not contribute")
    }

    private static func writesAndReadsUsageCache() throws {
        let root = try temporaryDirectory()
        let cache = CodexUsageCacheStore(root: root)
        let snapshot = CodexUsageSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_798_416_005),
            dayKey: "2027-01-01",
            profiles: [
                CodexUsageProfileSnapshot(
                    id: "work",
                    name: "Work",
                    inputTokens: 10,
                    cachedInputTokens: 2,
                    outputTokens: 5,
                    reasoningOutputTokens: 1,
                    totalTokens: 15,
                    errorMessage: nil
                )
            ]
        )

        try cache.write(snapshot)
        let loaded = try require(try cache.read(), "usage cache should load")

        try expect(loaded.dayKey == "2027-01-01", "cache should preserve day key")
        try expect(loaded.totalTokens == 15, "cache should preserve computed total")
        try expect(loaded.profiles.map(\.id) == ["work"], "cache should preserve profile ids")
    }

    private static func usage(input: UInt64, cached: UInt64, output: UInt64, reasoning: UInt64 = 0, total: UInt64) -> String {
        #"{"input_tokens": \#(input), "cached_input_tokens": \#(cached), "output_tokens": \#(output), "reasoning_output_tokens": \#(reasoning), "total_tokens": \#(total)}"#
    }

    private static func tokenLine(timestamp: Date, last: String? = nil, total: String? = nil) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let infoParts = [
            last.map { "\"last_token_usage\": \($0)" },
            total.map { "\"total_token_usage\": \($0)" }
        ].compactMap(\.self).joined(separator: ",")
        return """
        {"timestamp":"\(formatter.string(from: timestamp))","type":"event_msg","payload":{"type":"token_count","info":{\(infoParts)}}}
        """
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
