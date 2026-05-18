import SwiftUI

@main
struct SleepWatchProbeApp: App {
    @StateObject private var sessionManager = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            WatchContentView(manager: sessionManager)
        }
    }
}
