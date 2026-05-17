import XCTest
@testable import SleepKitProbe

@MainActor
final class ProbeLoggerTests: XCTestCase {
    func testWritesJSONL() throws {
        let url = temporaryLogURL()
        let logger = ProbeLogger(logURL: url)

        logger.appendSamples([TestRecords.sample()])

        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("\"type\":\"sleep_sample\""))
    }

    func testLoadsExistingLogAfterRestart() {
        let url = temporaryLogURL()
        let logger = ProbeLogger(logURL: url)
        logger.appendAppEvent(AppEventRecord(sessionId: nil, name: "test_event", detail: "persisted"))

        let reloadedLogger = ProbeLogger(logURL: url)

        XCTAssertEqual(reloadedLogger.appEvents.count, 1)
        XCTAssertEqual(reloadedLogger.appEvents.first?.name, "test_event")
    }

    private func temporaryLogURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jsonl")
    }
}
