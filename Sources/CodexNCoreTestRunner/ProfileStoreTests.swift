import Foundation
import CodexNCore

extension TestRunner {
    static func createsEmptyProfileDirectoriesWithoutCodexConfig() throws {
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

    static func createsProfilesWithResolvedCodexAppBundle() throws {
        let root = try temporaryDirectory()
        let legacyCodex = root.appending(path: "Codex.app")
        let chatGPTCodex = root.appending(path: "ChatGPT.app")
        try writeAppBundle(chatGPTCodex, bundleIdentifier: "com.openai.codex")
        let resolver = CodexDesktopAppResolver(candidateURLs: [legacyCodex, chatGPTCodex])
        let store = ProfileStore(root: root, appResolver: resolver)

        let profile = try store.createProfile(id: "work", name: "Work")

        try expect(profile.appBundle == chatGPTCodex, "new profiles should store the resolved Codex desktop app bundle")
    }

    static func refusesToCreateOverNonEmptyProfileDirectory() throws {
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

    static func rejectsProfileIDsWithPathLikeCharacters() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)

        do {
            _ = try store.createProfile(id: "work.profile", name: "Work")
            throw TestFailure("createProfile should reject profile ids with dots")
        } catch {
            try expect(String(describing: error).contains("Invalid profile id"), "wrong dotted id error: \(error)")
        }

        do {
            _ = try store.createProfile(id: "..", name: "Parent")
            throw TestFailure("createProfile should reject path-like profile ids")
        } catch {
            try expect(String(describing: error).contains("Invalid profile id"), "wrong parent id error: \(error)")
        }
    }

    static func importsDefaultCodexHomeAndElectronData() throws {
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

    static func createsAPIKeyProfileWithoutLeakingKeyToConfig() throws {
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

    static func rejectsInvalidAPIKeyProviderID() throws {
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

    static func rejectsAPIKeyProfileInputsWithIllegalCharacters() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)

        do {
            _ = try store.createAPIKeyProfile(
                id: "nested-provider",
                provider: "foo.bar",
                model: "gpt-5.5",
                baseURL: "https://example.test/v1",
                apiKey: "secret"
            )
            throw TestFailure("createAPIKeyProfile should reject provider ids that would create nested TOML tables")
        } catch {
            try expect(String(describing: error).contains("Invalid provider id"), "wrong provider dot error: \(error)")
        }

        do {
            _ = try store.createAPIKeyProfile(
                id: "bad-name",
                name: "Bad\nName",
                provider: "zl",
                model: "gpt-5.5",
                baseURL: "https://example.test/v1",
                apiKey: "secret"
            )
            throw TestFailure("createAPIKeyProfile should reject display names with control characters")
        } catch {
            try expect(String(describing: error).contains("Invalid display name"), "wrong display name error: \(error)")
        }

        do {
            _ = try store.createAPIKeyProfile(
                id: "bad-key",
                provider: "zl",
                model: "gpt-5.5",
                baseURL: "https://example.test/v1",
                apiKey: "secret\nnext"
            )
            throw TestFailure("createAPIKeyProfile should reject API keys with control characters")
        } catch {
            try expect(String(describing: error).contains("Invalid API key"), "wrong API key error: \(error)")
        }
    }

    static func rejectsInvalidAPIKeyBaseURL() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)

        do {
            _ = try store.createAPIKeyProfile(
                id: "bad-url",
                provider: "zl",
                model: "gpt-5.5",
                baseURL: "not a url",
                apiKey: "secret"
            )
            throw TestFailure("createAPIKeyProfile should reject invalid base URLs")
        } catch {
            try expect(String(describing: error).contains("Invalid base URL"), "wrong base URL error: \(error)")
        }
    }

    static func rejectsAPIKeyConfigValuesWithControlCharacters() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)

        do {
            _ = try store.createAPIKeyProfile(
                id: "bad-model",
                provider: "zl",
                model: "gpt-5.5\n[model_providers.attack]",
                baseURL: "https://example.test/v1",
                apiKey: "secret"
            )
            throw TestFailure("createAPIKeyProfile should reject model values with TOML control characters")
        } catch {
            try expect(String(describing: error).contains("Invalid config value"), "wrong model error: \(error)")
        }

        do {
            _ = try store.createAPIKeyProfile(
                id: "bad-url",
                provider: "zl",
                model: "gpt-5.5",
                baseURL: "https://example.test/v1\nenv_key=\"LEAK\"",
                apiKey: "secret"
            )
            throw TestFailure("createAPIKeyProfile should reject base URL values with TOML control characters")
        } catch {
            try expect(String(describing: error).contains("Invalid config value"), "wrong base URL error: \(error)")
        }
    }

    static func protectsProfileRegistryAndDirectoriesWithOwnerOnlyPermissions() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)
        let profile = try store.createAPIKeyProfile(
            id: "secure",
            provider: "zl",
            model: "gpt-5.5",
            baseURL: "https://example.test/v1",
            apiKey: "secret"
        )

        try expect(try permissions(root) == 0o700, "profile root should be 0700")
        try expect(try permissions(root.appending(path: "profiles.json")) == 0o600, "profiles.json should be 0600")
        try expect(try permissions(profile.codexHome.deletingLastPathComponent()) == 0o700, "profile directory should be 0700")
        try expect(try permissions(profile.codexHome) == 0o700, "codex-home should be 0700")
        try expect(try permissions(profile.electronUserData) == 0o700, "electron user data should be 0700")
        try expect(try permissions(profile.logDir) == 0o700, "logs should be 0700")
    }

    static func tightensExistingProfileRegistryPermissions() throws {
        let root = try temporaryDirectory()
        let registry = root.appending(path: "profiles.json")
        try #"{"profiles":[],"version":1}"#.write(to: registry, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: registry.path)

        _ = try ProfileStore(root: root).listProfiles()

        try expect(try permissions(root) == 0o700, "existing profile root should be tightened to 0700")
        try expect(try permissions(registry) == 0o600, "existing profiles.json should be tightened to 0600")
    }
}
