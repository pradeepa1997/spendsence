import SwiftUI
import SpendCore

/// Warns when the Shortcuts automation seems to have stopped delivering SMS.
struct AutomationHealthBanner: View {
    let health: AutomationHealth

    var body: some View {
        if let title {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text("Open Shortcuts → Automation and check the “Message contains LKR” automation is on and set to Run Immediately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
    }

    private var title: String? {
        switch health {
        case .healthy: nil
        case .neverReceived: "No bank SMS received yet"
        case .stale(let days): "No bank SMS received in \(days) days"
        }
    }
}
