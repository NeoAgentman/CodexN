import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case profiles
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .profiles: "Profiles"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .profiles: "person.2"
        case .about: "info.circle"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .profiles: .blue
        case .about: .indigo
        }
    }
}
