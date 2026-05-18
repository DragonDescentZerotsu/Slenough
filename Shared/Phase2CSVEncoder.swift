import Foundation

enum Phase2CSVEncoder {
    static func epochSummariesCSV(_ summaries: [EpochSummary]) -> String {
        let header = [
            "session_id",
            "epoch_id",
            "epoch_index",
            "start_date",
            "end_date",
            "motion_score",
            "accel_magnitude_mean",
            "accel_magnitude_std",
            "heart_rate_mean",
            "heart_rate_latest",
            "heart_rate_sample_count",
            "heart_rate_available",
            "battery_level",
            "predicted_state",
            "asleep_probability",
            "estimated_sleep_seconds",
            "algorithm_version"
        ].joined(separator: ",")

        let rows = summaries.map { summary in
            [
                summary.sessionId.uuidString,
                summary.id.uuidString,
                String(summary.epochIndex),
                isoString(summary.startDate),
                isoString(summary.endDate),
                number(summary.motionScore),
                optionalNumber(summary.accelMagnitudeMean),
                optionalNumber(summary.accelMagnitudeStd),
                optionalNumber(summary.heartRateMean),
                optionalNumber(summary.heartRateLatest),
                String(summary.heartRateSampleCount),
                String(summary.heartRateAvailable),
                optionalNumber(summary.batteryLevel),
                summary.predictedState.rawValue,
                number(summary.asleepProbability),
                number(summary.estimatedSleepSeconds),
                summary.algorithmVersion
            ].map(escape).joined(separator: ",")
        }

        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    static func watchEventsCSV(_ events: [WatchEventRecord]) -> String {
        let header = "session_id,event_id,timestamp,type,message"
        let rows = events.map { event in
            [
                event.sessionId?.uuidString ?? "",
                event.id.uuidString,
                isoString(event.timestamp),
                event.type,
                event.message ?? ""
            ].map(escape).joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func optionalNumber(_ value: Double?) -> String {
        guard let value else { return "" }
        return number(value)
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
