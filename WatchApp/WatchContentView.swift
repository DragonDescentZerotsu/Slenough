import SwiftUI

struct WatchContentView: View {
    @ObservedObject var manager: WatchSessionManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sleep Watch Probe")
                    .font(.headline)

                Text("Research probe only. Use a system alarm backup.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                metric("Status", manager.state.displayName)
                metric("Current State", manager.predictedState.displayName)
                metric("Estimated Sleep", durationString(manager.estimatedSleepSeconds))
                metric("Current HR", manager.latestHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "--")
                metric("Motion Score", String(format: "%.4f", manager.latestMotionScore))
                metric("Battery", manager.batteryLevel.map { "\(Int(($0 * 100).rounded()))%" } ?? "--")

                if manager.state == .running || manager.state == .starting {
                    Button("Stop Session") {
                        manager.stopSession(reason: "watch_button")
                    }
                    .tint(.red)
                } else {
                    Button("Start Session") {
                        manager.startSession(goalSeconds: SleepRuleConfig.default.sleepGoalSeconds)
                    }
                    .tint(.green)
                }

                HStack {
                    Button("Mark Awake") {
                        manager.markAwake()
                    }
                    Button("Mark Asleep") {
                        manager.markAsleep()
                    }
                }

                Button("Export/Sync Now") {
                    manager.syncNow()
                }
            }
            .padding()
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
        }
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

struct WatchContentView_Previews: PreviewProvider {
    static var previews: some View {
        WatchContentView(manager: WatchSessionManager())
            .previewDisplayName("Watch Probe")
    }
}
