import SwiftUI

struct ContentView: View {
    @StateObject private var manager = HealthKitManager()
    @StateObject private var watchManager = PhoneWatchConnectivityManager()

    var body: some View {
        TabView {
            DashboardView(manager: manager)
                .tabItem {
                    Label("Dashboard", systemImage: "gauge")
                }

            SampleListView(samples: manager.recentSamplesForDisplay)
                .tabItem {
                    Label("Samples", systemImage: "bed.double")
                }

            LogListView(events: manager.observerEvents, appEvents: manager.appEvents)
                .tabItem {
                    Label("Logs", systemImage: "list.bullet.rectangle")
                }

            WatchProbeView(watchManager: watchManager)
                .tabItem {
                    Label("Watch", systemImage: "applewatch")
                }

            ExportView(manager: manager)
                .tabItem {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
