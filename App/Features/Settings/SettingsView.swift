import SwiftUI
import UIKit
import UserNotifications
import SpendCore

struct SettingsView: View {
    @AppStorage(NotificationPrefs.transactionsKey) private var notifyTransactions = true
    @AppStorage(NotificationPrefs.budgetsKey) private var notifyBudgets = true
    @AppStorage(OnboardingState.completedKey) private var onboardingCompleted = true

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var permission: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section {
                LabeledContent("Permission", value: permissionText)
                if permission == .notDetermined {
                    Button("Allow notifications") {
                        Task {
                            await NotificationService.requestAuthorization()
                            await refreshPermission()
                        }
                    }
                } else if permission == .denied {
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                Toggle("Each logged transaction", isOn: $notifyTransactions)
                Toggle("Budget alerts (80% and 100%)", isOn: $notifyBudgets)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Transaction notifications include “Change category” and “Not an expense” actions.")
            }

            Section {
                Button("Show the setup guide again") { onboardingCompleted = false }
            } header: {
                Text("Setup")
            } footer: {
                Text("Walks through the Shortcuts automation and checks it with a test SMS.")
            }

            Section {
                Text("Long-press the Home Screen or Lock Screen → Edit → Add Widget → SpendSense. Choose Spending, Lock Screen or Quick Add.")
                    .font(.subheadline)
            } header: {
                Text("Widgets")
            }
        }
        .navigationTitle("Settings")
        .task(id: scenePhase) { await refreshPermission() }
    }

    private var permissionText: String {
        switch permission {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Off"
        case .notDetermined: "Not asked yet"
        @unknown default: "Unknown"
        }
    }

    private func refreshPermission() async {
        permission = await NotificationService.authorizationStatus()
    }
}

enum OnboardingState {
    static let completedKey = "onboarding.completed"
}
