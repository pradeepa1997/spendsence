import Foundation
import Observation
import UIKit
import UserNotifications
import WidgetKit
import SpendCore

/// A transaction to show from a deep link or notification.
struct TransactionLink: Identifiable, Hashable {
    let id: UUID
    /// Open straight into the edit form ("Change category").
    let edit: Bool
}

/// App-wide navigation state, driven by deep links (`spendsense://…`), widgets and notifications.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    enum Tab: Hashable {
        case dashboard, transactions, review, more
    }

    var tab: Tab = .dashboard
    var linkedTransaction: TransactionLink?
    var showAddTransaction = false
    var showBudgets = false

    func openTransaction(_ id: UUID, edit: Bool = false) {
        linkedTransaction = TransactionLink(id: id, edit: edit)
    }

    /// `spendsense://add`, `…/transaction/<uuid>`, `…/dashboard`, `…/review`, `…/budgets`.
    func handle(_ url: URL) {
        guard url.scheme == "spendsense" else { return }
        switch url.host() {
        case "add":
            showAddTransaction = true
        case "transaction":
            if let id = UUID(uuidString: url.lastPathComponent) { openTransaction(id) }
        case "dashboard":
            tab = .dashboard
        case "review":
            tab = .review
        case "budgets":
            tab = .dashboard
            showBudgets = true
        default:
            break
        }
    }
}

enum WidgetReloader {
    @MainActor
    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Call after the user changes data in the app: refresh widgets and send any budget alert now due.
enum AppEvents {
    static func dataChanged() {
        Task {
            await NotificationService.checkBudgets()
            await WidgetReloader.reload()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    private let notificationDelegate = NotificationDelegate()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        NotificationService.registerCategories()
        return true
    }
}
