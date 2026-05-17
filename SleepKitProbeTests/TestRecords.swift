import Foundation
@testable import SleepKitProbe

enum TestRecords {
    static func sample(
        start: TimeInterval = 0,
        end: TimeInterval = 60,
        valueName: String = "asleepCore",
        receivedAt: Date = Date(timeIntervalSince1970: 120)
    ) -> SleepSampleRecord {
        SleepSampleRecord(
            sessionId: nil,
            sampleUUID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            receivedAt: receivedAt,
            queryTriggeredAt: Date(timeIntervalSince1970: 100),
            sampleStartDate: Date(timeIntervalSince1970: start),
            sampleEndDate: Date(timeIntervalSince1970: end),
            durationSeconds: end - start,
            valueRaw: 3,
            valueName: valueName,
            sourceName: "Unit Test",
            sourceBundleIdentifier: "tests",
            deviceName: "Test Device",
            metadataDescription: "note=comma,newline\nquote\"",
            syncSource: "manualRefresh"
        )
    }
}
