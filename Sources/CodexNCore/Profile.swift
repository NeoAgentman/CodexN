import Foundation

public struct Profile: Codable, Equatable, Identifiable {
    public let id: String
    public var name: String
    public var codexHome: URL
    public var electronUserData: URL
    public var logDir: URL
    public var appBundle: URL
    public var defaultProvider: String
    public var apiKeyEnvName: String?
    public var apiKeyValue: String?
    public var createdAt: Date
    public var updatedAt: Date
}
