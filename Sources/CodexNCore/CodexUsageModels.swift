import Foundation

public struct CodexUsageProfile: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let codexHome: URL

    public init(id: String, name: String, codexHome: URL) {
        self.id = id
        self.name = name
        self.codexHome = codexHome
    }
}

public struct CodexUsageProfileSnapshot: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let inputTokens: UInt64
    public let cachedInputTokens: UInt64
    public let outputTokens: UInt64
    public let reasoningOutputTokens: UInt64
    public let totalTokens: UInt64
    public let errorMessage: String?

    public init(
        id: String,
        name: String,
        inputTokens: UInt64,
        cachedInputTokens: UInt64,
        outputTokens: UInt64,
        reasoningOutputTokens: UInt64,
        totalTokens: UInt64,
        errorMessage: String?
    ) {
        self.id = id
        self.name = name
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
        self.errorMessage = errorMessage
    }
}

public struct CodexUsageSnapshot: Codable, Equatable {
    public let version: Int
    public let generatedAt: Date
    public let dayKey: String
    public let profiles: [CodexUsageProfileSnapshot]
    public let totalTokens: UInt64

    public init(
        version: Int = 1,
        generatedAt: Date,
        dayKey: String,
        profiles: [CodexUsageProfileSnapshot],
        totalTokens: UInt64? = nil
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.dayKey = dayKey
        self.profiles = profiles
        self.totalTokens = totalTokens ?? profiles.reduce(0) { $0 + $1.totalTokens }
    }
}
