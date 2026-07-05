import Foundation

func randomAPIKeyEnvName(profileID: String) -> String {
    let sanitized = profileID
        .uppercased()
        .map { character in
            character.isLetter || character.isNumber ? character : "_"
        }
    let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
    return "CODEXN_API_KEY_\(String(sanitized))_\(suffix)"
}

func parseCodexNDate(_ value: String) -> Date? {
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    fractionalFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    if let date = fractionalFormatter.date(from: value) {
        return date
    }

    let plainFormatter = ISO8601DateFormatter()
    plainFormatter.formatOptions = [.withInternetDateTime]
    plainFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    return plainFormatter.date(from: value)
}

func formatCodexNDate(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
}

func expandHome(_ value: String) -> String {
    if value == "~" {
        return FileManager.default.homeDirectoryForCurrentUser.path
    }
    if value.hasPrefix("~/") {
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: String(value.dropFirst(2)))
            .path
    }
    return value
}
