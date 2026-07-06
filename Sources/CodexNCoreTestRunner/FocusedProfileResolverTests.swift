import Foundation
import CodexNCore

extension TestRunner {
    static func resolvesFocusedManagedProfileFromExplicitProfileEnvironment() throws {
        let snapshot = codexProcessSnapshot(environment: ["CODEXN_PROFILE_ID": "work"])

        let label = FocusedCodexProfileResolver.resolve(snapshot: snapshot, profiles: [])

        try expect(label == .profile(id: "work"), "explicit CodexN profile id should identify the focused profile")
    }

    static func resolvesFocusedManagedProfileFromExplicitProfileArgument() throws {
        let snapshot = codexProcessSnapshot(arguments: ["--codexn-profile-id=work"])

        let label = FocusedCodexProfileResolver.resolve(snapshot: snapshot, profiles: [])

        try expect(label == .profile(id: "work"), "explicit CodexN profile id argument should identify the focused profile")
    }

    static func resolvesFocusedManagedProfileFromCodexHomeEnvironment() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)
        let profile = try store.createProfile(id: "work", name: "Work")
        let snapshot = codexProcessSnapshot(environment: ["CODEX_HOME": profile.codexHome.path])

        let label = FocusedCodexProfileResolver.resolve(snapshot: snapshot, profiles: [profile])

        try expect(label == .profile(id: "work"), "CODEX_HOME should identify the focused profile")
    }

    static func resolvesFocusedManagedProfileFromElectronUserDataEnvironment() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)
        let profile = try store.createProfile(id: "personal", name: "Personal")
        let snapshot = codexProcessSnapshot(environment: ["CODEX_ELECTRON_USER_DATA_PATH": profile.electronUserData.path])

        let label = FocusedCodexProfileResolver.resolve(snapshot: snapshot, profiles: [profile])

        try expect(label == .profile(id: "personal"), "CODEX_ELECTRON_USER_DATA_PATH should identify the focused profile")
    }

    static func resolvesFocusedManagedProfileFromUserDataDirArgument() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)
        let profile = try store.createProfile(id: "zl", name: "ZL")
        let snapshot = codexProcessSnapshot(arguments: ["--user-data-dir=\(profile.electronUserData.path)"])

        let label = FocusedCodexProfileResolver.resolve(snapshot: snapshot, profiles: [profile])

        try expect(label == .profile(id: "zl"), "--user-data-dir should identify the focused profile")
    }

    static func resolvesDefaultCodexForCodexAppWithoutProfileMatch() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)
        let profile = try store.createProfile(id: "work", name: "Work")
        let snapshot = codexProcessSnapshot(arguments: ["--user-data-dir=/tmp/elsewhere"])

        let label = FocusedCodexProfileResolver.resolve(snapshot: snapshot, profiles: [profile])

        try expect(label == .defaultCodex, "unmatched Codex app should be treated as Default")
    }

    static func selectsRunningManagedProfileToActivate() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)
        let work = try store.createProfile(id: "work", name: "Work")
        let personal = try store.createProfile(id: "personal", name: "Personal")
        let snapshots = [
            codexProcessSnapshot(pid: 10, environment: ["CODEXN_PROFILE_ID": "work"]),
            codexProcessSnapshot(pid: 11, environment: ["CODEXN_PROFILE_ID": "personal"]),
            codexProcessSnapshot(pid: 12)
        ]

        let selected = FocusedCodexProfileResolver.matchingCodexProcessSnapshot(
            for: .profile(id: "personal"),
            snapshots: snapshots,
            profiles: [work, personal]
        )

        try expect(selected?.pid == 11, "managed profile activation should select the matching running Codex app")
    }

    static func selectsRunningDefaultCodexToActivate() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)
        let work = try store.createProfile(id: "work", name: "Work")
        let snapshots = [
            codexProcessSnapshot(pid: 20, environment: ["CODEXN_PROFILE_ID": "work"]),
            codexProcessSnapshot(pid: 21, arguments: ["--user-data-dir=/tmp/default-codex"])
        ]

        let selected = FocusedCodexProfileResolver.matchingCodexProcessSnapshot(
            for: .defaultCodex,
            snapshots: snapshots,
            profiles: [work]
        )

        try expect(selected?.pid == 21, "default activation should ignore managed profile apps and select Default Codex")
    }

    static func skipsCodexHelperProcessesWhenSelectingDefaultToActivate() throws {
        let helper = FocusedCodexProcessSnapshot(
            pid: 20,
            bundleIdentifier: nil,
            localizedName: "bare-modifier-monitor",
            executablePath: "/Applications/Codex.app/Contents/Resources/native/bare-modifier-monitor",
            arguments: [],
            environment: [:]
        )
        let service = FocusedCodexProcessSnapshot(
            pid: 21,
            bundleIdentifier: "com.openai.codex.helper",
            localizedName: "Codex (Service)",
            executablePath: "/Applications/Codex.app/Contents/Frameworks/Codex Framework.framework/Versions/149.0.7827.197/Helpers/Codex (Service).app/Contents/MacOS/Codex (Service)",
            arguments: [],
            environment: [:]
        )
        let computerUse = FocusedCodexProcessSnapshot(
            pid: 22,
            bundleIdentifier: "com.openai.sky.CUAService",
            localizedName: "Codex Computer Use",
            executablePath: "/Users/example/.codex/computer-use/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService",
            arguments: [],
            environment: [:]
        )
        let defaultCodex = codexProcessSnapshot(pid: 23)

        let selected = FocusedCodexProfileResolver.matchingCodexProcessSnapshot(
            for: .defaultCodex,
            snapshots: [helper, service, computerUse, defaultCodex],
            profiles: []
        )

        try expect(selected?.pid == 23, "default activation should select the main Codex app, not helper processes")
    }

    static func plansToReopenRunningCodexWhenMatchedAppHasNoVisibleWindow() throws {
        let plan = FocusedCodexProfileResolver.activationPlan(
            for: .defaultCodex,
            snapshots: [
                RunningCodexProcessSnapshot(process: codexProcessSnapshot(pid: 31), hasVisibleWindow: false)
            ],
            profiles: []
        )

        try expect(plan == .reopen(pid: 31), "matched running Codex without a visible window should be reopened")
    }

    static func plansToActivateRunningCodexWhenMatchedAppHasVisibleWindow() throws {
        let plan = FocusedCodexProfileResolver.activationPlan(
            for: .profile(id: "work"),
            snapshots: [
                RunningCodexProcessSnapshot(
                    process: codexProcessSnapshot(pid: 32, environment: ["CODEXN_PROFILE_ID": "work"]),
                    hasVisibleWindow: true
                )
            ],
            profiles: []
        )

        try expect(plan == .activate(pid: 32), "matched running Codex with a visible window should be activated")
    }

    static func returnsNilWhenNoRunningCodexProcessMatchesActivationTarget() throws {
        let root = try temporaryDirectory()
        let store = ProfileStore(root: root)
        let profile = try store.createProfile(id: "work", name: "Work")
        let snapshots = [
            codexProcessSnapshot(pid: 30, environment: ["CODEXN_PROFILE_ID": "work"])
        ]

        let selected = FocusedCodexProfileResolver.matchingCodexProcessSnapshot(
            for: .profile(id: "missing"),
            snapshots: snapshots,
            profiles: [profile]
        )

        try expect(selected == nil, "activation should fall back to launching when no running Codex process matches")
    }

    static func ignoresNonCodexForegroundApps() throws {
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

    static func formatsFocusedProfileMenuTitles() throws {
        try expect(FocusedCodexProfileResolver.menuBarTitle(for: .none) == "CodexN", "none title should be plain")
        try expect(FocusedCodexProfileResolver.menuBarTitle(for: .defaultCodex) == "CodexN | Default", "default title should be labeled")
        try expect(FocusedCodexProfileResolver.menuBarTitle(for: .profile(id: "work")) == "CodexN | work", "profile title should include id")
    }

    static func formatsFocusedProfileMenuBarText() throws {
        try expect(FocusedCodexProfileResolver.menuBarProfileText(for: .none) == "", "plain menu bar text should be empty")
        try expect(FocusedCodexProfileResolver.menuBarProfileText(for: .defaultCodex) == "Default", "default menu bar text should show Default")
        try expect(FocusedCodexProfileResolver.menuBarProfileText(for: .profile(id: "work")) == "work", "profile menu bar text should show id")
    }

    static func identifiesFocusedProfileTitleHighlightSegment() throws {
        try expect(FocusedCodexProfileResolver.menuBarHighlightedSegment(for: .none) == nil, "plain title should not have highlighted text")
        try expect(FocusedCodexProfileResolver.menuBarHighlightedSegment(for: .defaultCodex) == "Default", "default title should highlight Default")
        try expect(FocusedCodexProfileResolver.menuBarHighlightedSegment(for: .profile(id: "work")) == "work", "profile title should highlight profile id")
    }

    static func skipsProcessArgumentReadsForNonCodexApps() throws {
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
        try expect(
            !FocusedCodexProfileResolver.shouldReadProcessArguments(
                bundleIdentifier: nil,
                localizedName: "bare-modifier-monitor",
                executablePath: "/Applications/Codex.app/Contents/Resources/native/bare-modifier-monitor"
            ),
            "Codex resource helper processes should not require process argument reads"
        )
        try expect(
            !FocusedCodexProfileResolver.shouldReadProcessArguments(
                bundleIdentifier: "com.openai.codex.helper",
                localizedName: "Codex (Service)",
                executablePath: "/Applications/Codex.app/Contents/Frameworks/Codex Framework.framework/Versions/149.0.7827.197/Helpers/Codex (Service).app/Contents/MacOS/Codex (Service)"
            ),
            "Codex service helper processes should not require process argument reads"
        )
        try expect(
            !FocusedCodexProfileResolver.shouldReadProcessArguments(
                bundleIdentifier: "com.openai.sky.CUAService",
                localizedName: "Codex Computer Use",
                executablePath: "/Users/example/.codex/computer-use/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService"
            ),
            "Codex Computer Use should not be treated as the Codex desktop app"
        )
    }

    static func delaysWorkspaceDrivenMenuBarTitleUpdates() throws {
        try expect(
            MenuBarTitleUpdatePolicy.delay(for: .workspaceActivation) > 0,
            "workspace activation should not synchronously resize the status item title"
        )
        try expect(
            MenuBarTitleUpdatePolicy.delay(for: .workspaceTermination) > 0,
            "workspace termination should not synchronously resize the status item title"
        )
        try expect(
            MenuBarTitleUpdatePolicy.delay(for: .fallbackTimer) == 0,
            "fallback polling can refresh the status item title immediately"
        )
        try expect(
            MenuBarTitleUpdatePolicy.delay(for: .menuWillOpen) == 0,
            "menu opening should refresh the title immediately after AppKit starts menu tracking"
        )
    }

    static func usesTenSecondFocusedProfileFallbackInterval() throws {
        try expect(
            FocusedCodexProfileResolver.fallbackRefreshInterval == 10,
            "focused profile fallback polling interval should be 10 seconds"
        )
    }

    static func parsesKernelProcessArgumentsAndEnvironment() throws {
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

    static func codexProcessSnapshot(
        pid: Int32 = 42,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) -> FocusedCodexProcessSnapshot {
        FocusedCodexProcessSnapshot(
            pid: pid,
            bundleIdentifier: "com.openai.codex",
            localizedName: "Codex",
            executablePath: "/Applications/Codex.app/Contents/MacOS/Codex",
            arguments: arguments,
            environment: environment
        )
    }

    static func kernelProcessArgumentsData(
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

    static func appendNullTerminated(_ value: String, to data: inout Data) {
        data.append(value.data(using: .utf8)!)
        data.append(0)
    }
}
