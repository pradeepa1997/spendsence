import AppIntents
import Foundation
import SwiftData
import WidgetKit
import SpendCore

/// Widgets have nothing to configure; WidgetKit's async provider still needs an intent type.
struct SpendingWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Spending"
    static let description = IntentDescription("This month's spending from SpendSense.")
}

struct SpendingEntry: TimelineEntry {
    let date: Date
    /// Nil when the store can't be read (e.g. first run before the app has opened).
    let snapshot: DashboardSnapshot?

    static let placeholder = SpendingEntry(date: .now, snapshot: nil)
}

/// Reads the shared App Group store and refreshes every 30 minutes; the app and its intents also call
/// `WidgetCenter.reloadAllTimelines()` whenever data changes.
struct SpendingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SpendingEntry {
        .placeholder
    }

    func snapshot(for configuration: SpendingWidgetIntent, in context: Context) async -> SpendingEntry {
        context.isPreview ? .placeholder : Self.load()
    }

    func timeline(for configuration: SpendingWidgetIntent, in context: Context) async -> Timeline<SpendingEntry> {
        let entry = Self.load()
        return Timeline(entries: [entry], policy: .after(Date.now.addingTimeInterval(30 * 60)))
    }

    static func load(now: Date = .now) -> SpendingEntry {
        guard case .success(let container) = SharedStore.containerResult else {
            return SpendingEntry(date: now, snapshot: nil)
        }
        let context = ModelContext(container)
        return SpendingEntry(date: now, snapshot: try? DashboardSnapshot.load(in: context, now: now))
    }
}
