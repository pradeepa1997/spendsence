import Foundation
import SpendCore
import UserNotifications

/// User preferences for notifications (standard defaults: intents run in the app's process).
enum NotificationPrefs {
    static let transactionsKey = "notify.transactions"
    static let budgetsKey = "notify.budgets"
    static let sentBudgetAlertsKey = "notify.sentBudgetAlerts"

    static var transactionsEnabled: Bool {
        UserDefaults.standard.object(forKey: transactionsKey) as? Bool ?? true
    }

    static var budgetsEnabled: Bool {
        UserDefaults.standard.object(forKey: budgetsKey) as? Bool ?? true
    }
}

/// Local notifications: one per logged SMS, and budget alerts at 80% / 100%.
enum NotificationService {
    static let transactionCategory = "transaction"
    static let notExpenseAction = "notExpense"
    static let changeCategoryAction = "changeCategory"
    static let transactionIDKey = "transactionID"
    static let urlKey = "url"

    static func registerCategories() {
        let change = UNNotificationAction(identifier: changeCategoryAction, title: "Change category", options: [.foreground])
        let notExpense = UNNotificationAction(identifier: notExpenseAction, title: "Not an expense", options: [.destructive])
        let category = UNNotificationCategory(
            identifier: transactionCategory, actions: [change, notExpense], intentIdentifiers: [], options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// "LKR 2,450.00 – Keells Super" / "Groceries · HNB ••4821". Only for SMS that produced a transaction.
    static func notifyLogged(_ result: IngestionResult) async {
        guard NotificationPrefs.transactionsEnabled,
              result.status == .parsed || result.status == .needsReview,
              let id = result.transactionID,
              let transaction = await IngestionService.shared.transaction(id: id)
        else { return }

        var title = AmountFormatter.string(transaction.amount, currency: transaction.currency)
        switch transaction.type {
        case .credit: title = "+" + title
        case .refund: title = "Refund " + title
        case .debit, .transfer, .unknown: break
        }
        if let merchant = transaction.merchant { title += " – \(merchant)" }

        var details: [String] = [transaction.categoryName, transaction.accountDisplayName].compactMap { $0 }
        if result.status == .needsReview { details.append("Tap to review") }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = details.joined(separator: " · ")
        content.categoryIdentifier = transactionCategory
        content.threadIdentifier = "transactions"
        content.userInfo = [transactionIDKey: id.uuidString]
        add(content, identifier: "transaction-\(id.uuidString)")
    }

    /// Sends any budget alert not yet sent this month.
    static func checkBudgets(now: Date = .now) async {
        guard NotificationPrefs.budgetsEnabled,
              let snapshot = await IngestionService.shared.dashboardSnapshot(now: now)
        else { return }

        let month = BudgetAlertPlanner.monthKey(for: now)
        let defaults = UserDefaults.standard
        let stored = Set(defaults.stringArray(forKey: NotificationPrefs.sentBudgetAlertsKey) ?? [])
        var sent = BudgetAlertPlanner.pruned(stored, keepingMonth: month)

        for alert in BudgetAlertPlanner.alerts(for: snapshot.budgets, monthKey: month, alreadySent: sent) {
            let status = alert.status
            let spent = AmountFormatter.string(status.spent, currency: "LKR")
            let budget = AmountFormatter.string(status.budget, currency: "LKR")

            let content = UNMutableNotificationContent()
            content.title = alert.threshold >= 100
                ? "\(status.name) budget used up"
                : "\(status.name) budget at \(alert.threshold)%"
            content.body = "You've spent \(spent) of \(budget) this month."
            content.threadIdentifier = "budgets"
            content.userInfo = [urlKey: "spendsense://budgets"]
            add(content, identifier: "budget-\(alert.keys.first ?? UUID().uuidString)")
            sent.formUnion(alert.keys)
        }
        defaults.set(Array(sent), forKey: NotificationPrefs.sentBudgetAlertsKey)
    }

    private static func add(_ content: UNMutableNotificationContent, identifier: String) {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}

/// Handles taps and actions on our notifications.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let transactionID = (info[NotificationService.transactionIDKey] as? String).flatMap(UUID.init(uuidString:))
        let url = (info[NotificationService.urlKey] as? String).flatMap(URL.init(string:))

        if action == NotificationService.notExpenseAction, let transactionID {
            await IngestionService.shared.markNotATransaction(id: transactionID)
            await WidgetReloader.reload()
            return
        }

        let edit = action == NotificationService.changeCategoryAction
        await MainActor.run {
            if let transactionID {
                AppRouter.shared.openTransaction(transactionID, edit: edit)
            } else if let url {
                AppRouter.shared.handle(url)
            }
        }
    }
}
