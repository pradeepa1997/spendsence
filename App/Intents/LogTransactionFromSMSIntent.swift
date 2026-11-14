import AppIntents
import SpendCore

/// Called by the Shortcuts "Message" automation with the SMS body. Runs headless; never opens the app.
struct LogTransactionFromSMSIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Transaction from SMS"
    static let description = IntentDescription("Parses a bank SMS and saves it as a transaction.")
    static let openAppWhenRun = false

    @Parameter(title: "Message")
    var message: String

    @Parameter(title: "Sender")
    var sender: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$message) from \(\.$sender)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        // The single ingestion path. It never throws, persists the raw SMS first, and touches no UI.
        let result = await IngestionService.shared.ingest(body: message, sender: sender)
        await NotificationService.notifyLogged(result)
        await NotificationService.checkBudgets()
        await WidgetReloader.reload()
        return .result(value: result.summary, dialog: "\(result.summary)")
    }
}
