import Foundation

public struct CodexDesktopAppResolver {
    public static let bundleIdentifier = "com.openai.codex"
    public static let legacyCodexApp = URL(filePath: "/Applications/Codex.app")
    public static let chatGPTCodexApp = URL(filePath: "/Applications/ChatGPT.app")

    private let candidateURLs: [URL]
    private let fileManager: FileManager

    public init(
        candidateURLs: [URL] = [CodexDesktopAppResolver.legacyCodexApp, CodexDesktopAppResolver.chatGPTCodexApp],
        fileManager: FileManager = .default
    ) {
        self.candidateURLs = candidateURLs
        self.fileManager = fileManager
    }

    public func resolvedAppBundle(preferred: URL? = nil) -> URL {
        if let preferred, appBundleExists(preferred) {
            return preferred
        }

        if let candidate = candidateURLs.first(where: isCodexDesktopAppBundle) {
            return candidate
        }

        return preferred ?? CodexDesktopAppResolver.legacyCodexApp
    }

    private func isCodexDesktopAppBundle(_ url: URL) -> Bool {
        guard appBundleExists(url) else { return false }
        return bundleIdentifier(at: url) == CodexDesktopAppResolver.bundleIdentifier
    }

    private func appBundleExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func bundleIdentifier(at url: URL) -> String? {
        let infoPlist = url.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlist),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any] else {
            return nil
        }
        return dictionary["CFBundleIdentifier"] as? String
    }
}
