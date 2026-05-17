import SwiftUI

struct DashboardView: View {
    @ObservedObject var manager: HealthKitManager
    @State private var showingClearConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("HealthKit") {
                    InfoRow(title: "Available", value: manager.healthDataAvailable ? "Yes" : "No")
                    InfoRow(title: "Permission", value: manager.permissionStatusDescription)
                    InfoRow(title: "Observer", value: manager.observerRunning ? "Running" : "Stopped")
                    InfoRow(title: "Background Delivery", value: manager.backgroundDeliveryStatus)
                }

                Section("Probe") {
                    InfoRow(title: "Active Session", value: activeSessionText)
                    InfoRow(title: "Last Observer Trigger", value: DateFormatters.displayString(manager.lastObserverTriggeredAt))
                    InfoRow(title: "Last Anchored Samples", value: "\(manager.lastAnchoredAddedSampleCount)")
                    InfoRow(title: "Log Records", value: "\(manager.recordCount)")
                    InfoRow(title: "Log File Size", value: manager.logFileSizeDescription)
                    InfoRow(title: "Asleep-like Last 24h", value: manager.totalAsleepDurationDescription)
                    InfoRow(title: "Status", value: manager.statusMessage)
                }

                Section("Actions") {
                    Button("Request HealthKit Permission", systemImage: "heart.text.square") {
                        manager.requestHealthKitPermission()
                    }
                    Button("Start Observer", systemImage: "antenna.radiowaves.left.and.right") {
                        manager.startObserver()
                    }
                    Button("Manual Refresh Last 24h", systemImage: "clock.arrow.circlepath") {
                        manager.manualRefreshLast24Hours()
                    }
                    Button("Manual Refresh Last 7d", systemImage: "calendar.badge.clock") {
                        manager.manualRefreshLast7Days()
                    }

                    if manager.activeSession == nil {
                        Button("Start Night Probe", systemImage: "moon.zzz") {
                            manager.startNightProbe()
                        }
                    } else {
                        Button("End Night Probe", systemImage: "sun.max") {
                            manager.endNightProbe()
                        }
                    }

                    Button("Clear Local Logs", systemImage: "trash", role: .destructive) {
                        showingClearConfirmation = true
                    }
                }
            }
            .navigationTitle("SleepKit Probe")
            .alert("Clear local logs?", isPresented: $showingClearConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    manager.clearLocalLogs()
                }
            } message: {
                Text("This removes local samples, observer events, app events, the active probe session, and the saved anchored-query anchor.")
            }
        }
    }

    private var activeSessionText: String {
        guard let session = manager.activeSession else { return "None" }
        return "Started \(DateFormatters.displayString(session.startedAt))"
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}
