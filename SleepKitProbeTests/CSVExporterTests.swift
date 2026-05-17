import XCTest
@testable import SleepKitProbe

@MainActor
final class CSVExporterTests: XCTestCase {
    func testSleepSamplesHeaderIsStable() {
        let csv = CSVExporter.sleepSamplesCSV([])
        XCTAssertTrue(csv.hasPrefix("session_id,sample_uuid,received_at,query_triggered_at,sample_start,sample_end,duration_seconds,value_raw,value_name,source_name,source_bundle_identifier,device_name,sync_source,metadata_description\n"))
    }

    func testDateFormatIsStable() {
        let sample = TestRecords.sample(receivedAt: Date(timeIntervalSince1970: 0))
        let csv = CSVExporter.sleepSamplesCSV([sample])
        XCTAssertTrue(csv.contains("1970-01-01T00:00:00.000Z"))
    }

    func testEscapesCommaNewlineAndQuote() {
        let escaped = CSVExporter.render(header: ["field"], rows: [["comma,newline\nquote\""]])
        XCTAssertEqual(escaped, "field\n\"comma,newline\nquote\"\"\"\n")
    }
}
