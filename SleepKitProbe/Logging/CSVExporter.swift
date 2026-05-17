import Foundation

enum CSVExporter {
    static let sleepSamplesHeader = [
        "session_id",
        "sample_uuid",
        "received_at",
        "query_triggered_at",
        "sample_start",
        "sample_end",
        "duration_seconds",
        "value_raw",
        "value_name",
        "source_name",
        "source_bundle_identifier",
        "device_name",
        "sync_source",
        "metadata_description"
    ]

    static let observerEventsHeader = [
        "session_id",
        "event_id",
        "triggered_at",
        "anchored_query_started_at",
        "anchored_query_finished_at",
        "added_sample_count",
        "deleted_object_count",
        "error_description",
        "app_state_description"
    ]

    static func sleepSamplesCSV(_ records: [SleepSampleRecord]) -> String {
        let rows = records.map { record in
            [
                record.sessionId?.uuidString ?? "",
                record.sampleUUID.uuidString,
                DateFormatters.isoString(record.receivedAt),
                DateFormatters.isoString(record.queryTriggeredAt),
                DateFormatters.isoString(record.sampleStartDate),
                DateFormatters.isoString(record.sampleEndDate),
                String(format: "%.3f", record.durationSeconds),
                String(record.valueRaw),
                record.valueName,
                record.sourceName,
                record.sourceBundleIdentifier ?? "",
                record.deviceName ?? "",
                record.syncSource,
                record.metadataDescription ?? ""
            ]
        }
        return render(header: sleepSamplesHeader, rows: rows)
    }

    static func observerEventsCSV(_ records: [ObserverEventRecord]) -> String {
        let rows = records.map { record in
            [
                record.sessionId?.uuidString ?? "",
                record.id.uuidString,
                DateFormatters.isoString(record.triggeredAt),
                DateFormatters.isoString(record.anchoredQueryStartedAt),
                DateFormatters.isoString(record.anchoredQueryFinishedAt),
                String(record.addedSampleCount),
                String(record.deletedObjectCount),
                record.errorDescription ?? "",
                record.appStateDescription ?? ""
            ]
        }
        return render(header: observerEventsHeader, rows: rows)
    }

    static func render(header: [String], rows: [[String]]) -> String {
        ([header] + rows)
            .map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\n") + "\n"
    }

    nonisolated static func escape(_ field: String) -> String {
        let needsQuoting = field.contains(",") || field.contains("\n") || field.contains("\"") || field.contains("\r")
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuoting ? "\"\(escaped)\"" : escaped
    }
}
