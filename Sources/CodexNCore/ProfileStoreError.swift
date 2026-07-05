import Foundation

public enum ProfileStoreError: Error, CustomStringConvertible {
    case invalidProfileID(String)
    case profileAlreadyExists(String)
    case profileNotFound(String)
    case profileDirectoryNotEmpty(URL)
    case missingSourceDirectory(URL)
    case processFailed(String, Int32)
    case invalidProviderID(String)
    case emptyRequiredField(String)
    case invalidConfigValue(String)
    case invalidInputValue(String)
    case invalidBaseURL(String)

    public var description: String {
        switch self {
        case .invalidProfileID(let id):
            return "Invalid profile id: \(id)"
        case .profileAlreadyExists(let id):
            return "Profile already exists: \(id)"
        case .profileNotFound(let id):
            return "Profile not found: \(id)"
        case .profileDirectoryNotEmpty(let url):
            return "Profile directory is not empty: \(url.path)"
        case .missingSourceDirectory(let url):
            return "Source directory does not exist: \(url.path)"
        case .processFailed(let command, let code):
            return "\(command) exited with code \(code)"
        case .invalidProviderID(let id):
            return "Invalid provider id: \(id)"
        case .emptyRequiredField(let field):
            return "\(field) is required"
        case .invalidConfigValue(let field):
            return "Invalid config value: \(field)"
        case .invalidInputValue(let field):
            return "Invalid \(field)"
        case .invalidBaseURL(let value):
            return "Invalid base URL: \(value)"
        }
    }
}
