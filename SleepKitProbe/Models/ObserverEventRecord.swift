import Foundation

struct ObserverEventRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let sessionId: UUID?
    let triggeredAt: Date
    let anchoredQueryStartedAt: Date?
    let anchoredQueryFinishedAt: Date?
    let addedSampleCount: Int
    let deletedObjectCount: Int
    let errorDescription: String?
    let appStateDescription: String?

    init(
        id: UUID = UUID(),
        sessionId: UUID?,
        triggeredAt: Date,
        anchoredQueryStartedAt: Date?,
        anchoredQueryFinishedAt: Date?,
        addedSampleCount: Int,
        deletedObjectCount: Int,
        errorDescription: String?,
        appStateDescription: String?
    ) {
        self.id = id
        self.sessionId = sessionId
        self.triggeredAt = triggeredAt
        self.anchoredQueryStartedAt = anchoredQueryStartedAt
        self.anchoredQueryFinishedAt = anchoredQueryFinishedAt
        self.addedSampleCount = addedSampleCount
        self.deletedObjectCount = deletedObjectCount
        self.errorDescription = errorDescription
        self.appStateDescription = appStateDescription
    }
}
