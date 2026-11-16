import AppIntents
import SpendCore

/// Called by the Shortcuts "Message" automation with the SMS body.
///
/// It must run with **no user interaction**, including on the Lock Screen:
/// - it never opens the app,
/// - it may run while the iPhone is locked (the store's file protection allows writes after first unlock),
/// - it returns a value but **no dialog**, so Shortcuts has nothing to show or confirm. The user is told about the
///   transaction by SpendSense's own notification (`NotificationService.notifyLogged`).
struct LogTransactionFromSMSIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Transaction from SMS"
    static let description = IntentDescription("Parses a bank SMS and saves it as a transaction.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Message")
    var message: String

    @Parameter(title: "Sender")
    var sender: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$message) from \(\.$sender)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // The single ingestion path. It never throws, persists the raw SMS first, and touches no UI.
        // Saving comes first, so the transaction is kept even if iOS ends the run right after.
        let result = await IngestionService.shared.ingest(body: message, sender: sender)
        await NotificationService.notifyLogged(result)
        await NotificationService.checkBudgets()
        await WidgetReloader.reload()
        return .result(value: result.summary)
    }
}
