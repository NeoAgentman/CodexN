import Foundation
import CodexNCore

@main
struct TestRunner {
    static func main() throws {
        try createsEmptyProfileDirectoriesWithoutCodexConfig()
        try refusesToCreateOverNonEmptyProfileDirectory()
        try rejectsProfileIDsWithPathLikeCharacters()
        try importsDefaultCodexHomeAndElectronData()
        try createsAPIKeyProfileWithoutLeakingKeyToConfig()
        try rejectsInvalidAPIKeyProviderID()
        try rejectsAPIKeyProfileInputsWithIllegalCharacters()
        try rejectsInvalidAPIKeyBaseURL()
        try rejectsAPIKeyConfigValuesWithControlCharacters()
        try protectsProfileRegistryAndDirectoriesWithOwnerOnlyPermissions()
        try tightensExistingProfileRegistryPermissions()
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
        try formatsFocusedProfileMenuBarText()
        try identifiesFocusedProfileTitleHighlightSegment()
        try formatsMenuBarUsageTitles()
        try skipsProcessArgumentReadsForNonCodexApps()
        try usesTenSecondFocusedProfileFallbackInterval()
        try parsesKernelProcessArgumentsAndEnvironment()
        try scansTodayUsageFromCodexHomes()
        try scansRecentlyModifiedOlderCodexSessionPartitionsOnly()
        try computesUsageListBarWidths()
        try formatsTokenUsageValues()
        try writesAndReadsUsageCache()
        print("CodexNCoreTestRunner: all tests passed")
    }
}
