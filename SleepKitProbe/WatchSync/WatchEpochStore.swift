import Foundation

final class WatchEpochStore {
    private(set) var summaries: [EpochSummary] = []
    private(set) var events: [WatchEventRecord] = []

    private let logURL: URL
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    init(logURL: URL = FileStore.applicationSupportDirectory.appendingPathComponent("watch_epoch_log.jsonl")) {
        self.logURL = logURL
        loadExistingLog()
    }

    var recordCount: Int {
        summaries.count + events.count
    }

    func append(summary: EpochSummary) {
        guard !summaries.contains(where: {
            $0.id == summary.id ||
            ($0.sessionId == summary.sessionId &&
             $0.epochIndex == summary.epochIndex &&
             $0.startDate == summary.startDate &&
             $0.endDate == summary.endDate)
        }) else {
            return
        }
        summaries.append(summary)
        appendLine(WatchEpochLogLine(type: "epoch_summary", payload: summary))
    }

    func append(event: WatchEventRecord) {
        events.append(event)
        appendLine(WatchEventLogLine(type: "watch_event", payload: event))
    }

    func clear() {
        summaries.removeAll()
        events.removeAll()
        try? FileManager.default.removeItem(at: logURL)
    }

    func writeEpochCSV(to directory: URL = FileStore.exportDirectory) throws -> URL {
        let url = directory.appendingPathComponent("watch_epoch_summaries.csv")
        try Phase2CSVEncoder.epochSummariesCSV(summaries).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func writeEventCSV(to directory: URL = FileStore.exportDirectory) throws -> URL {
        let url = directory.appendingPathComponent("watch_events.csv")
        try Phase2CSVEncoder.watchEventsCSV(events).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func loadExistingLog() {
        guard let content = try? String(contentsOf: logURL, encoding: .utf8) else { return }
        for line in content.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let typeLine = try? decoder.decode(LogTypeLine.self, from: data) else {
                continue
            }
            switch typeLine.type {
            case "epoch_summary":
                if let decoded = try? decoder.decode(WatchEpochLogLine.self, from: data) {
                    summaries.append(decoded.payload)
                }
            case "watch_event":
                if let decoded = try? decoder.decode(WatchEventLogLine.self, from: data) {
                    events.append(decoded.payload)
                }
            default:
                continue
            }
        }
    }

    private func appendLine<T: Encodable>(_ line: T) {
        guard let data = try? encoder.encode(line),
              let encodedLine = String(data: data, encoding: .utf8) else {
            return
        }
        let payload = encodedLine + "\n"
        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(payload.utf8))
        } else {
            try? payload.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}

private struct LogTypeLine: Decodable {
    let type: String
}

private struct WatchEpochLogLine: Codable {
    let type: String
    let payload: EpochSummary
}

private struct WatchEventLogLine: Codable {
    let type: String
    let payload: WatchEventRecord
}
