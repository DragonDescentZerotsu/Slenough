import Foundation

enum JSONLExporter {
    private struct TypedRecord<Payload: Encodable>: Encodable {
        let type: String
        let payload: Payload
    }

    static func export(
        samples: [SleepSampleRecord],
        observerEvents: [ObserverEventRecord],
        appEvents: [AppEventRecord]
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(DateFormatters.iso8601)
        encoder.outputFormatting = [.sortedKeys]

        var lines: [String] = []
        for sample in samples {
            lines.append(try encodeLine(TypedRecord(type: "sleep_sample", payload: sample), encoder: encoder))
        }
        for event in observerEvents {
            lines.append(try encodeLine(TypedRecord(type: "observer_event", payload: event), encoder: encoder))
        }
        for event in appEvents {
            lines.append(try encodeLine(TypedRecord(type: "app_event", payload: event), encoder: encoder))
        }
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    private static func encodeLine<T: Encodable>(_ value: T, encoder: JSONEncoder) throws -> String {
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
