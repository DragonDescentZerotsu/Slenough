import SwiftUI

struct SampleListView: View {
    let samples: [SleepSampleRecord]

    var body: some View {
        NavigationStack {
            List(samples) { sample in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(sample.valueName)
                            .font(.headline)
                        Spacer()
                        Text(durationText(sample.durationSeconds))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("\(DateFormatters.displayString(sample.sampleStartDate)) - \(DateFormatters.displayString(sample.sampleEndDate))")
                    Text("Source: \(sample.sourceName)")
                    Text("Received: \(DateFormatters.displayString(sample.receivedAt))")
                    Text("Latency: \(durationText(sample.latencySeconds))")
                    Text("Sync: \(sample.syncSource)")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(.vertical, 4)
            }
            .navigationTitle("Sleep Samples")
            .toolbar {
                Text("Last 7d")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .overlay {
                if samples.isEmpty {
                    ContentUnavailableView("No Samples", systemImage: "bed.double", description: Text("Request permission, then run Manual Refresh Last 24h or wait for observer updates."))
                }
            }
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let sign = duration < 0 ? "-" : ""
        let absolute = abs(Int(duration))
        let hours = absolute / 3600
        let minutes = (absolute % 3600) / 60
        let seconds = absolute % 60
        if hours > 0 {
            return "\(sign)\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(sign)\(minutes)m \(seconds)s"
        }
        return "\(sign)\(seconds)s"
    }
}
