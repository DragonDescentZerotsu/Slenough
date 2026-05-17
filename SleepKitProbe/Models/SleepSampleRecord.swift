import Foundation

struct SleepSampleRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let sessionId: UUID?
    let sampleUUID: UUID
    let receivedAt: Date
    let queryTriggeredAt: Date?
    let sampleStartDate: Date
    let sampleEndDate: Date
    let durationSeconds: TimeInterval
    let valueRaw: Int
    let valueName: String
    let sourceName: String
    let sourceBundleIdentifier: String?
    let deviceName: String?
    let metadataDescription: String?
    let syncSource: String

    init(
        id: UUID = UUID(),
        sessionId: UUID?,
        sampleUUID: UUID,
        receivedAt: Date,
        queryTriggeredAt: Date?,
        sampleStartDate: Date,
        sampleEndDate: Date,
        durationSeconds: TimeInterval,
        valueRaw: Int,
        valueName: String,
        sourceName: String,
        sourceBundleIdentifier: String?,
        deviceName: String?,
        metadataDescription: String?,
        syncSource: String
    ) {
        self.id = id
        self.sessionId = sessionId
        self.sampleUUID = sampleUUID
        self.receivedAt = receivedAt
        self.queryTriggeredAt = queryTriggeredAt
        self.sampleStartDate = sampleStartDate
        self.sampleEndDate = sampleEndDate
        self.durationSeconds = durationSeconds
        self.valueRaw = valueRaw
        self.valueName = valueName
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.deviceName = deviceName
        self.metadataDescription = metadataDescription
        self.syncSource = syncSource
    }

    var latencySeconds: TimeInterval {
        receivedAt.timeIntervalSince(sampleEndDate)
    }
}
