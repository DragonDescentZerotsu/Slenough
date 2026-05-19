import Foundation
import WatchConnectivity

final class WatchConnectivitySender: NSObject, WCSessionDelegate {
    var onConfigReceived: ((SleepRuleConfig) -> Void)?
    var onSyncRequested: (() -> Void)?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var queuedUserInfo: [[String: Any]] = []
    private var pendingUserInfo: [[String: Any]] = []

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func send(summary: EpochSummary) {
        guard WCSession.isSupported(),
              let data = try? encoder.encode(summary) else {
            return
        }

        let payload: [String: Any] = ["type": "epoch_summary", "payload": data]
        guard WCSession.default.activationState == .activated else {
            pendingUserInfo.append(payload)
            return
        }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { [weak self] _ in
                self?.queuedUserInfo.append(payload)
            }
        }
        WCSession.default.transferUserInfo(payload)
    }

    func flushQueuedUserInfo() {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated else {
            return
        }
        pendingUserInfo.forEach { WCSession.default.transferUserInfo($0) }
        pendingUserInfo.removeAll()
        queuedUserInfo.forEach { WCSession.default.transferUserInfo($0) }
        queuedUserInfo.removeAll()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            flushQueuedUserInfo()
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo)
    }

    private func handle(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        switch type {
        case "sleep_rule_config":
            guard let data = message["payload"] as? Data,
                  let config = try? decoder.decode(SleepRuleConfig.self, from: data) else {
                return
            }
            DispatchQueue.main.async {
                self.onConfigReceived?(config)
            }
        case "request_sync":
            DispatchQueue.main.async {
                self.onSyncRequested?()
            }
        default:
            break
        }
    }
}
