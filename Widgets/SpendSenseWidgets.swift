import SwiftUI
import WidgetKit

struct SpendingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SpendSense.Spending", intent: SpendingWidgetIntent.self, provider: SpendingProvider()) { entry in
            SpendingWidgetView(entry: entry)
        }
        .configurationDisplayName("Spending")
        .description("This month's spending, budget use and top categories.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LockScreenSpendingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SpendSense.LockScreen", intent: SpendingWidgetIntent.self, provider: SpendingProvider()) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Spending (Lock Screen)")
        .description("Spent this month, or how much of your budgets you've used.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct QuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SpendSense.QuickAdd", intent: SpendingWidgetIntent.self, provider: SpendingProvider()) { entry in
            QuickAddWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick add")
        .description("One tap to add a cash expense.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct SpendSenseWidgetBundle: WidgetBundle {
    var body: some Widget {
        SpendingWidget()
        LockScreenSpendingWidget()
        QuickAddWidget()
    }
}
