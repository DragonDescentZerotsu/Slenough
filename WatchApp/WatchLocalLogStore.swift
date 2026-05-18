import Foundation

final class WatchLocalLogStore {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private let logURL: URL

    init(logURL: URL = WatchLocalLogStore.defaultLogURL) {
        self.logURL = logURL
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func appendEpoch(_ epoch: WatchEpoch) {
        append(WatchEpochLogLine(type: "watch_epoch", payload: epoch))
    }

    func appendEvent(_ event: WatchEventRecord) {
        append(WatchEventLogLine(type: "watch_event", payload: event))
    }

    private func append<T: Encodable>(_ envelope: T) {
        guard let data = try? encoder.encode(envelope),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        let payload = line + "\n"
        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(payload.utf8))
        } else {
            try? payload.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    private static var defaultLogURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("SleepKitProbeWatch", isDirectory: true)
            .appendingPathComponent("watch_probe_log.jsonl")
    }
}

private struct WatchEpochLogLine: Encodable {
    let type: String
    let payload: WatchEpoch
}

private struct WatchEventLogLine: Encodable {
    let type: String
    let payload: WatchEventRecord
}
