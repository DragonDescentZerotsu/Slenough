import SwiftUI

struct LogListView: View {
    let events: [ObserverEventRecord]
    let appEvents: [AppEventRecord]

    var body: some View {
        NavigationStack {
            List {
                Section("Observer Events") {
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(DateFormatters.displayString(event.triggeredAt))
                                .font(.headline)
                            Text("Added samples: \(event.addedSampleCount)")
                            Text("Deleted objects: \(event.deletedObjectCount)")
                            Text("Started: \(DateFormatters.displayString(event.anchoredQueryStartedAt))")
                            Text("Finished: \(DateFormatters.displayString(event.anchoredQueryFinishedAt))")
                            if let errorDescription = event.errorDescription, !errorDescription.isEmpty {
                                Text("Error: \(errorDescription)")
                                    .foregroundStyle(.red)
                            }
                            if let appStateDescription = event.appStateDescription {
                                Text("App state: \(appStateDescription)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                        .padding(.vertical, 4)
                    }
                }

                Section("App Events") {
                    ForEach(appEvents.prefix(40)) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.name)
                                .font(.headline)
                            Text(DateFormatters.displayString(event.createdAt))
                            if let detail = event.detail {
                                Text(detail)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Logs")
            .overlay {
                if events.isEmpty && appEvents.isEmpty {
                    ContentUnavailableView("No Logs", systemImage: "list.bullet.rectangle")
                }
            }
        }
    }
}
