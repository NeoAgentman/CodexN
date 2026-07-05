import Foundation

enum CodexConfigWriter {
    static func writeAPIKeyConfig(profile: Profile, provider: String, model: String, baseURL: String, envName: String) throws {
        let config = """
        model = "\(tomlString(model))"
        model_provider = "\(tomlString(provider))"

        [model_providers.\(provider)]
        name = "\(tomlString(provider))"
        base_url = "\(tomlString(baseURL))"
        env_key = "\(tomlString(envName))"
        wire_api = "responses"

        """
        try config.write(to: profile.codexHome.appending(path: "config.toml"), atomically: true, encoding: .utf8)
    }

    private static func tomlString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
