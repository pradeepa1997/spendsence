import SwiftData
import SwiftUI
import SpendCore

/// Paste an SMS and push it through the exact same path the App Intent uses (`IngestionService.ingest`).
struct SimulateSMSView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var messageText = ""
    @State private var sender = ""
    @State private var lastResult: IngestionResult?
    @State private var isIngesting = false
    @State private var showDeleteConfirmation = false
    @State private var errorText: String?

    private var canIngest: Bool {
        !isIngesting && !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("SMS body") {
                TextEditor(text: $messageText)
                    .font(.body.monospaced())
                    .frame(minHeight: 140)
            }

            Section("Sender (optional)") {
                TextField("e.g. COMBANK", text: $sender)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }

            Section {
                Button {
                    Task { await ingest() }
                } label: {
                    HStack {
                        Text("Ingest")
                        if isIngesting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!canIngest)
            }

            if let lastResult {
                Section("Result") {
                    HStack(alignment: .firstTextBaseline) {
                        StatusPill(status: lastResult.status)
                        Text(lastResult.summary)
                    }
                }
            }

            if let errorText {
                Section {
                    Text(errorText).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Simulate")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu("Load sample") {
                    ForEach(SampleMessages.all) { sample in
                        Button(sample.title) {
                            messageText = sample.body
                            sender = sample.sender ?? ""
                            lastResult = nil
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete all data", systemImage: "trash", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Delete all transactions, messages, accounts, rules and categories?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete all data", role: .destructive) { deleteAll() }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func ingest() async {
        isIngesting = true
        errorText = nil
        let trimmedSender = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        lastResult = await IngestionService.shared.ingest(
            body: messageText,
            sender: trimmedSender.isEmpty ? nil : trimmedSender,
            source: .simulated
        )
        isIngesting = false
    }

    /// Dev convenience. Runs on the view's main context so the @Query lists refresh immediately.
    private func deleteAll() {
        do {
            try TransactionEditor(context: modelContext).deleteAllData()
            lastResult = nil
        } catch {
            errorText = "Delete failed: \(error.localizedDescription)"
        }
    }
}
