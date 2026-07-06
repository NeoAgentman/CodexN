import Foundation

public enum MenuBarTitleUpdateReason {
    case fallbackTimer
    case menuWillOpen
    case workspaceActivation
    case workspaceTermination
}

public enum MenuBarTitleUpdatePolicy {
    public static let workspaceEventDelay: TimeInterval = 0.35

    public static func delay(for reason: MenuBarTitleUpdateReason) -> TimeInterval {
        switch reason {
        case .workspaceActivation, .workspaceTermination:
            return workspaceEventDelay
        case .fallbackTimer, .menuWillOpen:
            return 0
        }
    }
}
