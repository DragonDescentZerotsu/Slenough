import XCTest
@testable import SleepKitProbe

@MainActor
final class SleepSampleMapperTests: XCTestCase {
    func testKnownRawValuesMapToReadableNames() {
        XCTAssertEqual(SleepSampleMapper.valueName(rawValue: 0), "inBed")
        XCTAssertEqual(SleepSampleMapper.valueName(rawValue: 2), "awake")
        XCTAssertEqual(SleepSampleMapper.valueName(rawValue: 3), "asleepCore")
        XCTAssertEqual(SleepSampleMapper.valueName(rawValue: 4), "asleepDeep")
        XCTAssertEqual(SleepSampleMapper.valueName(rawValue: 5), "asleepREM")
    }

    func testUnknownRawValueDoesNotCrash() {
        XCTAssertEqual(SleepSampleMapper.valueName(rawValue: 999), "unknown(999)")
    }
}
