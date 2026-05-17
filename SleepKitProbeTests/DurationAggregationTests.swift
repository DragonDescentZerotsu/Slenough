import XCTest
@testable import SleepKitProbe

@MainActor
final class DurationAggregationTests: XCTestCase {
    func testAsleepLikeValuesAreCounted() {
        let records = [
            TestRecords.sample(start: 0, end: 60, valueName: "asleepCore"),
            TestRecords.sample(start: 60, end: 120, valueName: "asleepREM")
        ]

        XCTAssertEqual(DurationAggregation.asleepDuration(records: records), 120)
    }

    func testAwakeAndInBedAreNotCounted() {
        let records = [
            TestRecords.sample(start: 0, end: 60, valueName: "awake"),
            TestRecords.sample(start: 60, end: 120, valueName: "inBed")
        ]

        XCTAssertEqual(DurationAggregation.asleepDuration(records: records), 0)
    }

    func testOverlappingAsleepSamplesAreNotDoubleCounted() {
        let records = [
            TestRecords.sample(start: 0, end: 100, valueName: "asleepCore"),
            TestRecords.sample(start: 50, end: 150, valueName: "asleepDeep")
        ]

        XCTAssertEqual(DurationAggregation.asleepDuration(records: records), 150)
    }

    func testRangeBoundedDurationClipsLongSamples() {
        let records = [
            TestRecords.sample(start: 0, end: 1_000_000, valueName: "asleepCore")
        ]

        let duration = DurationAggregation.asleepDuration(
            records: records,
            in: Date(timeIntervalSince1970: 100)...Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(duration, 100)
    }
}
