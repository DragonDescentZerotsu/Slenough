import Foundation
import Testing
@testable import SleepKitProbe

struct Phase2CSVEncoderTests {
    @Test func epochSummaryCSVContainsStableHeaderAndValues() {
        let summary = EpochSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            sessionId: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
            epochIndex: 4,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 60),
            motionScore: 0.1234567,
            accelMagnitudeMean: 1.01,
            accelMagnitudeStd: 0.02,
            heartRateMean: 62.5,
            heartRateLatest: 63,
            heartRateSampleCount: 2,
            heartRateAvailable: true,
            batteryLevel: 0.77,
            predictedState: .asleep,
            asleepProbability: 0.8,
            estimatedSleepSeconds: 60,
            algorithmVersion: "test-version"
        )

        let csv = Phase2CSVEncoder.epochSummariesCSV([summary])

        #expect(csv.contains("session_id,epoch_id,epoch_index,start_date,end_date,motion_score"))
        #expect(csv.contains("00000000-0000-0000-0000-000000000020"))
        #expect(csv.contains("1970-01-01T00:00:00.000Z"))
        #expect(csv.contains("0.123457"))
        #expect(csv.contains("asleep"))
        #expect(csv.contains("test-version"))
    }

    @Test func watchEventCSVQuotesSpecialCharacters() {
        let event = WatchEventRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!,
            sessionId: nil,
            timestamp: Date(timeIntervalSince1970: 0),
            type: "connectivity_failed",
            message: "comma,newline\nquote\""
        )

        let csv = Phase2CSVEncoder.watchEventsCSV([event])

        #expect(csv.contains("\"comma,newline\nquote\"\"\""))
    }
}
