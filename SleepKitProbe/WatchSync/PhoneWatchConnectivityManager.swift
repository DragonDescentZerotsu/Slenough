import Combine
import Foundation
import WatchConnectivity

final class PhoneWatchConnectivityManager: NSObject, ObservableObject {
    @Published private(set) var connectionDescription = "Not Connected"
    @Published private(set) var diagnosticsDescription = "Unavailable"
    @Published private(set) var lastEpochReceivedAt: Date?
    @Published private(set) var latestSummary: EpochSummary?
    @Published private(set) var statusMessage = "Idle"
    @Published var exportedURLs: [URL] = []

    private let store = WatchEpochStore()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private var consecutiveMissingReports = 0
    private static let lastInstalledSeenAtKey = "SleepKitProbe.watch.lastInstalledSeenAt"
    private static let lastWatchAliveSeenAtKey = "SleepKitProbe.watch.lastAliveSeenAt"

    override init() {
        super.init()
        latestSummary = store.summaries.last
        lastEpochReceivedAt = store.summaries.last?.endDate
        activate()
    }

    var summaries: [EpochSummary] {
        store.summaries
    }

    var recordCount: Int {
        store.recordCount
    }

    func refreshConnectionStatus() {
        if WCSession.isSupported(), WCSession.default.activationState != .activated {
            WCSession.default.activate()
        }
        updateConnectionDescription()
    }

    func activate() {
        guard WCSession.isSupported() else {
            connectionDescription = "Unsupported"
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        updateConnectionDescription()
    }

    func sendGoalToWatch(config: SleepRuleConfig = .default) {
        guard WCSession.isSupported(),
              let data = try? encoder.encode(config) else {
            statusMessage = "WatchConnectivity unavailable"
            return
        }
        guard WCSession.default.activationState == .activated else {
            statusMessage = "WatchConnectivity is still activating"
            updateConnectionDescription()
            return
        }

        let payload: [String: Any] = ["type": "sleep_rule_config", "payload": data]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { [weak self] error in
                DispatchQueue.main.async {
                    self?.statusMessage = "Send goal failed: \(error.localizedDescription)"
                }
            }
            statusMessage = "Goal sent to reachable Watch"
        } else {
            WCSession.default.transferUserInfo(payload)
            statusMessage = "Goal queued for Watch"
        }
    }

    func requestWatchSync() {
        guard WCSession.isSupported() else { return }
        guard WCSession.default.activationState == .activated else {
            statusMessage = "WatchConnectivity is still activating"
            updateConnectionDescription()
            return
        }
        let payload: [String: Any] = ["type": "request_sync"]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { [weak self] error in
                DispatchQueue.main.async {
                    self?.statusMessage = "Sync request failed: \(error.localizedDescription)"
                }
            }
            statusMessage = "Sync requested"
        } else {
            statusMessage = "Watch is not reachable; waiting for transferUserInfo"
        }
    }

    func exportEpochCSV() {
        do {
            exportedURLs = [try store.writeEpochCSV()]
            statusMessage = "Exported watch_epoch_summaries.csv"
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func exportEventCSV() {
        do {
            exportedURLs = [try store.writeEventCSV()]
            statusMessage = "Exported watch_events.csv"
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func clearLocalWatchLogs() {
        store.clear()
        latestSummary = nil
        lastEpochReceivedAt = nil
        exportedURLs = []
        statusMessage = "Cleared local Watch logs on iPhone"
    }

    private func handleMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        switch type {
        case "epoch_summary":
            guard let data = message["payload"] as? Data,
                  let summary = try? decoder.decode(EpochSummary.self, from: data) else {
                statusMessage = "Received malformed epoch summary"
                return
            }
            store.append(summary: summary)
            latestSummary = summary
            lastEpochReceivedAt = Date()
            statusMessage = "Received epoch \(summary.epochIndex)"
        case "epoch_summary_batch":
            guard let data = message["payload"] as? Data,
                  let summaries = try? decoder.decode([EpochSummary].self, from: data),
                  let latest = summaries.max(by: { $0.epochIndex < $1.epochIndex }) else {
                statusMessage = "Received malformed epoch batch"
                return
            }
            summaries.sorted { $0.epochIndex < $1.epochIndex }.forEach { summary in
                store.append(summary: summary)
            }
            latestSummary = latest
            lastEpochReceivedAt = Date()
            statusMessage = "Received \(summaries.count) epochs through batch"
        case "watch_app_alive":
            rememberWatchAliveSeen()
            statusMessage = "Received Watch alive ping"
            updateConnectionDescription()
        default:
            statusMessage = "Received \(type)"
        }
    }

    private func updateConnectionDescription() {
        guard WCSession.isSupported() else {
            connectionDescription = "Unsupported"
            diagnosticsDescription = "WCSession unsupported on this device"
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated else {
            connectionDescription = "Activating"
            diagnosticsDescription = "activation=\(session.activationState.rawValue)"
            return
        }
        diagnosticsDescription = diagnostics(for: session)
        if session.isPaired && session.isWatchAppInstalled {
            consecutiveMissingReports = 0
            rememberInstalledWatchAppSeen()
            connectionDescription = session.isReachable ? "Connected" : "Installed, Not Reachable"
        } else if session.isPaired {
            consecutiveMissingReports += 1
            if recentlySawWatchAlive {
                connectionDescription = "Watch App Alive, Install State Stale"
            } else if recentlySawInstalledWatchApp {
                connectionDescription = "Previously Installed, Not Reachable"
            } else {
                connectionDescription = "Paired, Watch App Missing"
            }
        } else {
            consecutiveMissingReports = 0
            connectionDescription = "Not Paired"
        }
    }

    private func diagnostics(for session: WCSession) -> String {
        let lastSeen = lastInstalledWatchAppSeenAt.map(Self.diagnosticDateString) ?? "never"
        let lastAlive = lastWatchAliveSeenAt.map(Self.diagnosticDateString) ?? "never"
        return "paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) reachable=\(session.isReachable) activation=\(session.activationState.rawValue) missingReports=\(consecutiveMissingReports) lastInstalledSeenAt=\(lastSeen) lastWatchAliveAt=\(lastAlive)"
    }

    nonisolated private static func diagnosticDateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func rememberInstalledWatchAppSeen() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastInstalledSeenAtKey)
    }

    private func rememberWatchAliveSeen() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastWatchAliveSeenAtKey)
    }

    private var lastInstalledWatchAppSeenAt: Date? {
        let value = UserDefaults.standard.double(forKey: Self.lastInstalledSeenAtKey)
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    private var lastWatchAliveSeenAt: Date? {
        let value = UserDefaults.standard.double(forKey: Self.lastWatchAliveSeenAtKey)
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    private var recentlySawWatchAlive: Bool {
        if let lastWatchAliveSeenAt,
           Date().timeIntervalSince(lastWatchAliveSeenAt) < 10 * 60 {
            return true
        }
        return false
    }

    private var recentlySawInstalledWatchApp: Bool {
        if let lastInstalledWatchAppSeenAt,
           Date().timeIntervalSince(lastInstalledWatchAppSeenAt) < 7 * 86_400 {
            return true
        }
        if let lastEpochReceivedAt,
           Date().timeIntervalSince(lastEpochReceivedAt) < 7 * 86_400 {
            return true
        }
        return false
    }
}

extension PhoneWatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.updateConnectionDescription()
            if let error {
                self.statusMessage = "Activation failed: \(error.localizedDescription)"
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async {
            self.updateConnectionDescription()
        }
    }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        DispatchQueue.main.async {
            self.updateConnectionDescription()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.updateConnectionDescription()
        }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.updateConnectionDescription()
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            self.handleMessage(message)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async {
            self.handleMessage(userInfo)
        }
    }
}
