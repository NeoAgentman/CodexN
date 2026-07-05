import Foundation

enum ProfileInputValidator {
    static func validateProfileID(_ id: String) throws {
        let pattern = #"^[A-Za-z0-9_-]+$"#
        if id.range(of: pattern, options: .regularExpression) == nil {
            throw ProfileStoreError.invalidProfileID(id)
        }
    }

    static func validateProviderID(_ id: String) throws {
        let pattern = #"^[A-Za-z0-9_-]+$"#
        if id.range(of: pattern, options: .regularExpression) == nil {
            throw ProfileStoreError.invalidProviderID(id)
        }
    }

    static func validateRequired(_ field: String, _ value: String) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ProfileStoreError.emptyRequiredField(field)
        }
    }

    static func validateTOMLConfigValue(_ field: String, _ value: String) throws {
        if value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            throw ProfileStoreError.invalidConfigValue(field)
        }
    }

    static func validateDisplayName(_ value: String) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || containsControlCharacter(value) {
            throw ProfileStoreError.invalidInputValue("display name")
        }
    }

    static func validateAPIKey(_ value: String) throws {
        if containsControlCharacter(value) {
            throw ProfileStoreError.invalidInputValue("API key")
        }
    }

    static func validateBaseURL(_ value: String) throws {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false
        else {
            throw ProfileStoreError.invalidBaseURL(value)
        }
    }

    private static func containsControlCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }
}
