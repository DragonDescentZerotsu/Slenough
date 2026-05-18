import SwiftUI

struct WatchProbeView: View {
    @StateObject private var watchManager = PhoneWatchConnectivityManager()
    @State private var showingShareSheet = false
    @State private var showingClearConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("SleepEnough Probe") {
                    InfoLine(title: "Watch Connection", value: watchManager.connectionDescription)
                    InfoLine(title: "Current Watch Session", value: currentSessionDescription)
                    InfoLine(title: "Estimated Sleep", value: durationString(watchManager.latestSummary?.estimatedSleepSeconds ?? 0))
                    InfoLine(title: "Current State", value: watchManager.latestSummary?.predictedState.displayName ?? "Unknown")
                    InfoLine(title: "Last Epoch Received", value: DateFormatters.displayString(watchManager.lastEpochReceivedAt))
                    InfoLine(title: "Heart Rate", value: heartRateDescription)
                    InfoLine(title: "Motion Score", value: motionScoreDescription)
                    InfoLine(title: "Watch Battery", value: batteryDescription)
                    InfoLine(title: "Epoch Records", value: "\(watchManager.recordCount)")
                    InfoLine(title: "Status", value: watchManager.statusMessage)
                }

                Section("Actions") {
                    Button("Send Goal to Watch", systemImage: "target") {
                        watchManager.sendGoalToWatch()
                    }
                    Button("Request Watch Sync", systemImage: "arrow.triangle.2.circlepath") {
                        watchManager.requestWatchSync()
                    }
                    Button("Export Epoch CSV", systemImage: "tablecells") {
                        watchManager.exportEpochCSV()
                        showingShareSheet = !watchManager.exportedURLs.isEmpty
                    }
                    Button("Export Watch Event CSV", systemImage: "list.bullet.rectangle") {
                        watchManager.exportEventCSV()
                        showingShareSheet = !watchManager.exportedURLs.isEmpty
                    }
                    Button("Clear iPhone Watch Logs", systemImage: "trash", role: .destructive) {
                        showingClearConfirmation = true
                    }
                }

                Section("Safety") {
                    Text("This is a research probe, not a reliable alarm. Do not rely on it as your only wake-up alarm.")
                }
            }
            .navigationTitle("Watch Probe")
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: watchManager.exportedURLs)
            }
            .alert("Clear Watch logs received on iPhone?", isPresented: $showingClearConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    watchManager.clearLocalWatchLogs()
                }
            }
        }
    }

    private var currentSessionDescription: String {
        guard let summary = watchManager.latestSummary else { return "Not Running" }
        return "Last session \(summary.sessionId.uuidString.prefix(8))"
    }

    private var heartRateDescription: String {
        guard let heartRate = watchManager.latestSummary?.heartRateLatest else { return "--" }
        return "\(Int(heartRate.rounded())) bpm"
    }

    private var motionScoreDescription: String {
        guard let motionScore = watchManager.latestSummary?.motionScore else { return "--" }
        return String(format: "%.4f", motionScore)
    }

    private var batteryDescription: String {
        guard let battery = watchManager.latestSummary?.batteryLevel else { return "--" }
        return "\(Int((battery * 100).rounded()))%"
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

private struct InfoLine: View {
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
