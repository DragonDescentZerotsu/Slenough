import Foundation

final class ProbeLogger {
    private(set) var samples: [SleepSampleRecord] = []
    private(set) var observerEvents: [ObserverEventRecord] = []
    private(set) var appEvents: [AppEventRecord] = []

    let logURL: URL

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(DateFormatters.iso8601)
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(DateFormatters.iso8601)
        return decoder
    }()

    init(logURL: URL = FileStore.applicationSupportDirectory.appendingPathComponent("probe_log.jsonl")) {
        self.logURL = logURL
        loadExistingLog()
    }

    var recordCount: Int {
        samples.count + observerEvents.count + appEvents.count
    }

    var logFileSize: Int64 {
        FileStore.fileSize(at: logURL)
    }

    func appendSamples(_ records: [SleepSampleRecord]) {
        guard !records.isEmpty else { return }
        samples.append(contentsOf: records)
        appendLines(records.map { .sleepSample($0) })
    }

    func appendObserverEvent(_ record: ObserverEventRecord) {
        observerEvents.append(record)
        appendLines([.observerEvent(record)])
    }

    func appendAppEvent(_ record: AppEventRecord) {
        appEvents.append(record)
        appendLines([.appEvent(record)])
    }

    func clear() {
        samples.removeAll()
        observerEvents.removeAll()
        appEvents.removeAll()
        try? FileManager.default.removeItem(at: logURL)
    }

    func writeCSVExports(to directory: URL = FileStore.exportDirectory) throws -> [URL] {
        let samplesURL = directory.appendingPathComponent("sleep_samples.csv")
        let eventsURL = directory.appendingPathComponent("observer_events.csv")
        try CSVExporter.sleepSamplesCSV(samples).write(to: samplesURL, atomically: true, encoding: .utf8)
        try CSVExporter.observerEventsCSV(observerEvents).write(to: eventsURL, atomically: true, encoding: .utf8)
        return [samplesURL, eventsURL]
    }

    func writeJSONLExport(to directory: URL = FileStore.exportDirectory) throws -> URL {
        let url = directory.appendingPathComponent("sleepkit_probe_log.jsonl")
        let content = try JSONLExporter.export(samples: samples, observerEvents: observerEvents, appEvents: appEvents)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func loadExistingLog() {
        guard let content = try? String(contentsOf: logURL, encoding: .utf8) else { return }
        for line in content.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let decoded = try? decoder.decode(ProbeLogLine.self, from: data) else {
                continue
            }
            switch decoded {
            case .sleepSample(let record):
                samples.append(record)
            case .observerEvent(let record):
                observerEvents.append(record)
            case .appEvent(let record):
                appEvents.append(record)
            }
        }
    }

    private func appendLines(_ lines: [ProbeLogLine]) {
        guard !lines.isEmpty else { return }
        let encodedLines = lines.compactMap { line -> String? in
            guard let data = try? encoder.encode(line) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        guard !encodedLines.isEmpty else { return }

        let payload = encodedLines.joined(separator: "\n") + "\n"
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
