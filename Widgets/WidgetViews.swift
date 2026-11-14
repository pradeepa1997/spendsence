import SwiftUI
import WidgetKit
import SpendCore

// MARK: - Helpers

extension Color {
    /// `#RRGGBB`; invalid input gives grey. (The app has its own copy; widgets are a separate target.)
    init(widgetHex hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard digits.count == 6, let value = UInt64(digits, radix: 16) else {
            self = .gray
            return
        }
        let red: Double = Double((value >> 16) & 0xFF) / 255.0
        let green: Double = Double((value >> 8) & 0xFF) / 255.0
        let blue: Double = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

enum WidgetLinks {
    static let dashboard = URL(string: "spendsense://dashboard")
    static let add = URL(string: "spendsense://add")
    static let budgets = URL(string: "spendsense://budgets")
}

extension DashboardSnapshot {
    var spentText: String { AmountFormatter.compact(summary.totalSpent, currency: summary.currency) }
}

private struct NoDataView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "chart.pie")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open SpendSense to get started")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct BudgetBar: View {
    let fraction: Double

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        let color: Color = fraction >= 1 ? .red : (fraction >= 0.8 ? .orange : .green)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(color).frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Spending widget (Home Screen)

struct SpendingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SpendingEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                if family == .systemMedium {
                    medium(snapshot)
                } else {
                    small(snapshot)
                }
            } else {
                NoDataView()
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .widgetURL(WidgetLinks.dashboard)
    }

    private func small(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Spent in \(snapshot.monthName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(snapshot.spentText)
                .font(.title2.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer(minLength: 0)
            if let fraction = snapshot.overallBudgetFraction {
                BudgetBar(fraction: fraction)
                Text("\(Int((fraction * 100).rounded()))% of budget")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Income \(AmountFormatter.compact(snapshot.summary.totalIncome, currency: snapshot.summary.currency))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if snapshot.awaitingReview > 0 {
                Label("\(snapshot.awaitingReview) to review", systemImage: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ snapshot: DashboardSnapshot) -> some View {
        let top = Array(snapshot.summary.byCategory.prefix(3))
        let largest = top.first?.amount ?? 1
        return HStack(alignment: .top, spacing: 16) {
            small(snapshot)
            VStack(alignment: .leading, spacing: 8) {
                if top.isEmpty {
                    Text("No spending yet this month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(top) { category in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Image(systemName: category.symbol)
                                .font(.caption2)
                                .foregroundStyle(Color(widgetHex: category.colorHex))
                            Text(category.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(AmountFormatter.compact(category.amount, currency: ""))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Color(widgetHex: category.colorHex))
                                .frame(width: proxy.size.width * share(category.amount, of: largest))
                        }
                        .frame(height: 5)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func share(_ amount: Decimal, of largest: Decimal) -> CGFloat {
        guard largest > 0 else { return 0 }
        return CGFloat(NSDecimalNumber(decimal: amount / largest).doubleValue)
    }
}

// MARK: - Lock Screen widgets

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SpendingEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
            .widgetURL(WidgetLinks.dashboard)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .accessoryCircular:
                circular(snapshot)
            case .accessoryInline:
                Text("\(snapshot.spentText) in \(snapshot.monthName)")
            default:
                rectangular(snapshot)
            }
        } else {
            Image(systemName: "chart.pie")
        }
    }

    @ViewBuilder
    private func circular(_ snapshot: DashboardSnapshot) -> some View {
        if let fraction = snapshot.overallBudgetFraction {
            Gauge(value: min(fraction, 1)) {
                Image(systemName: "chart.pie.fill")
            } currentValueLabel: {
                Text("\(Int((fraction * 100).rounded()))")
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            VStack(spacing: 0) {
                Image(systemName: "chart.pie.fill").font(.caption2)
                Text(AmountFormatter.compact(snapshot.summary.totalSpent, currency: ""))
                    .font(.caption2.bold())
                    .minimumScaleFactor(0.5)
            }
        }
    }

    private func rectangular(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Spent in \(snapshot.monthName)")
                .font(.caption2)
                .widgetAccentable()
            Text(snapshot.spentText)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let top = snapshot.summary.byCategory.first {
                Text("Most: \(top.name)")
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Quick add

struct QuickAddWidgetView: View {
    let entry: SpendingEntry

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text("Add expense")
                .font(.headline)
            if let snapshot = entry.snapshot {
                Text("\(snapshot.spentText) this month")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .widgetURL(WidgetLinks.add)
    }
}
