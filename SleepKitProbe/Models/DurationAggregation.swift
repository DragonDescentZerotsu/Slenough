import Foundation

enum DurationAggregation {
    static let asleepLikeValueNames: Set<String> = [
        "asleepUnspecified",
        "asleepCore",
        "asleepDeep",
        "asleepREM"
    ]

    static func isAsleepLike(valueName: String) -> Bool {
        asleepLikeValueNames.contains(valueName)
    }

    static func asleepDuration(records: [SleepSampleRecord]) -> TimeInterval {
        let intervals = records
            .filter { isAsleepLike(valueName: $0.valueName) }
            .map { ($0.sampleStartDate, $0.sampleEndDate) }
            .filter { $0.1 > $0.0 }
            .sorted { $0.0 < $1.0 }

        guard var current = intervals.first else { return 0 }
        var total: TimeInterval = 0

        for interval in intervals.dropFirst() {
            if interval.0 <= current.1 {
                current.1 = max(current.1, interval.1)
            } else {
                total += current.1.timeIntervalSince(current.0)
                current = interval
            }
        }
        total += current.1.timeIntervalSince(current.0)
        return total
    }

    static func asleepDuration(records: [SleepSampleRecord], in range: ClosedRange<Date>) -> TimeInterval {
        let intervals = records
            .filter { isAsleepLike(valueName: $0.valueName) }
            .compactMap { record -> (Date, Date)? in
                let clippedStart = max(record.sampleStartDate, range.lowerBound)
                let clippedEnd = min(record.sampleEndDate, range.upperBound)
                guard clippedEnd > clippedStart else { return nil }
                return (clippedStart, clippedEnd)
            }
            .sorted { $0.0 < $1.0 }

        guard var current = intervals.first else { return 0 }
        var total: TimeInterval = 0

        for interval in intervals.dropFirst() {
            if interval.0 <= current.1 {
                current.1 = max(current.1, interval.1)
            } else {
                total += current.1.timeIntervalSince(current.0)
                current = interval
            }
        }
        total += current.1.timeIntervalSince(current.0)
        return total
    }
}
