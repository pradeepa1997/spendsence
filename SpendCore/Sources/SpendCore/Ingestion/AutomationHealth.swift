import Foundation

/// Whether the Shortcuts automation still seems to be delivering SMS. Automations can silently stop
/// (iOS update, the user edits the shortcut), so the app warns when nothing has arrived for a while.
public enum AutomationHealth: Sendable, Equatable {
    /// An SMS arrived within `staleAfterDays`.
    case healthy
    /// No SMS has ever arrived from the automation.
    case neverReceived
    /// The last SMS arrived this many whole days ago (more than `staleAfterDays`).
    case stale(days: Int)

    public static let staleAfterDays = 5

    public static func evaluate(lastSMSAt: Date?, now: Date = .now, calendar: Calendar = .current) -> AutomationHealth {
        guard let lastSMSAt else { return .neverReceived }
        let days = calendar.dateComponents([.day], from: lastSMSAt, to: now).day ?? 0
        return days > staleAfterDays ? .stale(days: days) : .healthy
    }
}
