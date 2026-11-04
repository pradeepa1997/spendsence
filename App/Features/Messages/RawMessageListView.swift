import SwiftData
import SwiftUI
import SpendCore

/// Debug log of every SMS the app received, with its parse status.
struct RawMessageListView: View {
    @Query(sort: \RawMessage.receivedAt, order: .reverse)
    private var messages: [RawMessage]

    var body: some View {
        NavigationStack {
            Group {
                if messages.isEmpty {
                    ContentUnavailableView(
                        "No messages yet",
                        systemImage: "message",
                        description: Text("SMS received from the Shortcuts automation or the Simulate tab appear here.")
                    )
                } else {
                    List(messages) { message in
                        NavigationLink {
                            RawMessageDetailView(message: message)
                        } label: {
                            RawMessageRow(message: message)
                        }
                    }
                }
            }
            .navigationTitle("Messages")
        }
    }
}

private struct RawMessageRow: View {
    let message: RawMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                StatusPill(status: message.status)
                Spacer()
                Text(message.receivedAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(message.body)
                .font(.subheadline)
                .lineLimit(2)
            Text(message.sender ?? "Unknown sender")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct RawMessageDetailView: View {
    let message: RawMessage

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Status") { StatusPill(status: message.status) }
                if let reason = message.failureReason {
                    LabeledContent("Reason", value: reason)
                }
                LabeledContent("Parser version", value: "\(message.parserVersion)")
                if let transaction = message.transaction {
                    NavigationLink("View transaction") {
                        TransactionDetailView(transaction: transaction)
                    }
                }
            }
            Section("Message") {
                Text(message.body)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                LabeledContent("Sender", value: message.sender ?? "—")
                LabeledContent("Received") {
                    Text(message.receivedAt, format: .dateTime)
                }
            }
        }
        .navigationTitle("Message")
        .navigationBarTitleDisplayMode(.inline)
    }
}
