import SwiftUI

struct ExportView: View {
    @ObservedObject var manager: HealthKitManager
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section("Privacy") {
                    Text("Exports contain health-related sleep timeline data. Files are generated locally and are not uploaded by this app.")
                }

                Section("Files") {
                    Button("Export CSV", systemImage: "tablecells") {
                        manager.exportCSV()
                        showingShareSheet = !manager.exportedURLs.isEmpty
                    }

                    Button("Export JSONL", systemImage: "curlybraces") {
                        manager.exportJSONL()
                        showingShareSheet = !manager.exportedURLs.isEmpty
                    }

                    InfoLine(title: "Records", value: "\(manager.recordCount)")
                    InfoLine(title: "Status", value: manager.statusMessage)
                }
            }
            .navigationTitle("Export")
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: manager.exportedURLs)
            }
        }
    }
}

private struct InfoLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
