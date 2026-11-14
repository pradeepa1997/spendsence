import SwiftUI
import SpendCore

/// First-launch guide: privacy → banks → Shortcuts automation → verify with a test SMS → notifications.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, banks, automation, verify, notifications
    }

    let onFinish: () -> Void

    @State private var step: Step = .welcome
    @State private var useRs = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                    .padding(.horizontal)
                    .padding(.top, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        content
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .toolbar {
                if step != .welcome {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { move(by: -1) }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Skip") { onFinish() }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            WelcomeStep { move(by: 1) }
        case .banks:
            BanksStep(useRs: $useRs) { move(by: 1) }
        case .automation:
            AutomationStep(useRs: useRs) { move(by: 1) }
        case .verify:
            VerifyStep { move(by: 1) }
        case .notifications:
            NotificationsStep { onFinish() }
        }
    }

    private func move(by delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation { step = next }
    }
}

// MARK: - Steps

private struct StepHeader: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.top, 8)
    }
}

private struct WelcomeStep: View {
    let next: () -> Void

    var body: some View {
        StepHeader(
            symbol: "lock.shield.fill",
            title: "Welcome to SpendSense",
            subtitle: "Your bank SMS become a tidy expense tracker, automatically."
        )
        VStack(alignment: .leading, spacing: 14) {
            Label("Everything stays on this iPhone. No account, no servers, no analytics.", systemImage: "iphone")
            Label("Only messages that match your automation reach the app.", systemImage: "message.badge")
            Label("You can review, edit or delete anything it logs.", systemImage: "checkmark.circle")
        }
        .font(.subheadline)
        PrimaryButton(title: "Get started", action: next)
    }
}

private struct BanksStep: View {
    @Binding var useRs: Bool
    let next: () -> Void

    private let banks = ["HNB", "DFCC", "NDB", "Seylan", "People's Bank"]

    var body: some View {
        StepHeader(
            symbol: "building.columns.fill",
            title: "Your banks",
            subtitle: "SpendSense knows these SMS formats. Other banks usually work too, and you can teach it."
        )
        VStack(alignment: .leading, spacing: 8) {
            ForEach(banks, id: \.self) { bank in
                Label(bank, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.primary)
            }
        }
        Toggle("Some of my banks write “Rs” instead of “LKR”", isOn: $useRs)
        PrimaryButton(title: "Continue", action: next)
    }
}

private struct AutomationStep: View {
    let useRs: Bool
    let next: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        StepHeader(
            symbol: "gearshape.2.fill",
            title: "Connect your SMS",
            subtitle: "iOS doesn't let apps read messages, so a Shortcuts automation hands bank SMS to SpendSense."
        )
        VStack(alignment: .leading, spacing: 14) {
            instruction(1, "Open **Shortcuts** → **Automation** → **+** (New Automation).")
            instruction(2, "Choose **Message**. Tap **Message Contains**, type **LKR**. Leave Sender empty.")
            instruction(3, "Select **Run Immediately** and turn **Notify When Run** off. Tap **Next**.")
            instruction(4, "Tap **New Blank Automation** → **Add Action** → search **Log Transaction from SMS**.")
            instruction(5, "Tap **Message** → **Shortcut Input**, then tap it again → **Content**. Set **Sender** to **Shortcut Input → Sender**. Tap **Done**.")
            if useRs {
                instruction(6, "Repeat the same automation with **Rs** as the keyword.")
            }
        }
        Button {
            if let url = URL(string: "shortcuts://") { openURL(url) }
        } label: {
            Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        PrimaryButton(title: "I've set it up", action: next)
    }

    private func instruction(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(text)
                .font(.subheadline)
        }
    }
}

private struct VerifyStep: View {
    let next: () -> Void

    /// Messages from slightly before this step count too (the user may have sent the test already).
    @State private var startedAt = Date.now.addingTimeInterval(-10 * 60)
    @State private var received: RawMessageSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                symbol: "checkmark.message.fill",
                title: "Send a test SMS",
                subtitle: "From another phone, text this iPhone:"
            )
            Text("LKR 100.00 debited from card ending 4321 at TEST SHOP")
                .font(.body.monospaced())
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .textSelection(.enabled)

            if let received {
                Label("Received! Status: \(received.status.label)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Text("You can delete the test transaction later from the Transactions tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PrimaryButton(title: "Continue", action: next)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Waiting for the message…")
                        .foregroundStyle(.secondary)
                }
                Text("Nothing arriving? Check the automation is set to Run Immediately and its Message is Shortcut Input → Content. You can also run the action by hand in Shortcuts to test it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("I'll test it later", action: next)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
        .task {
            // Poll the store rather than @Query, so a message saved by the intent shows up reliably.
            while received == nil && !Task.isCancelled {
                if let latest = await IngestionService.shared.latestAutomationMessage(), latest.receivedAt >= startedAt {
                    received = latest
                    break
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

private struct NotificationsStep: View {
    let finish: () -> Void

    @State private var asked = false
    @State private var granted = false

    var body: some View {
        StepHeader(
            symbol: "bell.badge.fill",
            title: "Stay in the loop",
            subtitle: "Get a quiet notification for each logged transaction (with a quick “Not an expense” action) and when a budget reaches 80% or 100%."
        )
        if asked {
            Label(granted ? "Notifications are on" : "Notifications are off. You can turn them on later in Settings.",
                  systemImage: granted ? "checkmark.circle.fill" : "bell.slash")
                .foregroundStyle(granted ? Color.green : Color.secondary)
            PrimaryButton(title: "Start using SpendSense", action: finish)
        } else {
            PrimaryButton(title: "Allow notifications") {
                Task {
                    granted = await NotificationService.requestAuthorization()
                    asked = true
                }
            }
            Button("Not now", action: finish)
                .frame(maxWidth: .infinity)
        }
    }
}
