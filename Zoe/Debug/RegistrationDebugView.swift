#if DEBUG
import SwiftUI

struct RegistrationDebugView: View {
    @ObservedObject var keyManager: KeyManager
    @State private var isResetting = false

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    LabeledContent("State") {
                        Text(stateDescription(keyManager.state))
                            .foregroundStyle(stateColor(keyManager.state))
                            .bold()
                    }
                    LabeledContent("Signing Available",
                                   value: keyManager.isSigningAvailable ? "YES ✅" : "NO ❌")
                    LabeledContent("KID", value: keyManager.kid.map {
                        String($0.prefix(12)) + "..."
                    } ?? "—")
                    if let err = keyManager.lastError {
                        LabeledContent("Last Error", value: err)
                            .foregroundStyle(.red)
                    }
                }

                Section("Registration Log") {
                    if keyManager.registrationLog.isEmpty {
                        Text("No log entries yet")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        ForEach(keyManager.registrationLog) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.formatted)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(logColor(entry.level))
                                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Actions") {
                    Button(role: .destructive) {
                        isResetting = true
                        Task {
                            await keyManager.resetRegistration()
                            isResetting = false
                        }
                    } label: {
                        HStack {
                            if isResetting {
                                ProgressView().scaleEffect(0.8)
                            }
                            Text(isResetting ? "Resetting..." : "Reset & Retry Registration")
                        }
                    }
                    .disabled(isResetting)
                }
            }
            .navigationTitle("Registration Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func stateDescription(_ state: RegistrationState) -> String {
        switch state {
        case .unknown:         return "unknown"
        case .registering:     return "registering"
        case .registered:      return "registered"
        case .retrying:        return "retrying"
        case .failedPermanent: return "failedPermanent"
        }
    }

    private func stateColor(_ state: RegistrationState) -> Color {
        switch state {
        case .registered:                return .green
        case .failedPermanent:           return .red
        case .registering, .retrying:    return .orange
        case .unknown:                   return .secondary
        }
    }

    private func logColor(_ level: RegistrationLogEntry.Level) -> Color {
        switch level {
        case .info:    return .primary
        case .success: return .green
        case .warning: return .orange
        case .error:   return .red
        }
    }
}
#endif
