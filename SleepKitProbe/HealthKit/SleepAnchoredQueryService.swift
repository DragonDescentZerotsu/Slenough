import Foundation
import HealthKit

struct AnchoredQueryResult {
    let samples: [SleepSampleRecord]
    let deletedObjectCount: Int
    let queryStartedAt: Date
    let queryFinishedAt: Date
    let error: Error?
}

struct AnchorBootstrapResult {
    let historicalSampleCount: Int
    let deletedObjectCount: Int
    let queryStartedAt: Date
    let queryFinishedAt: Date
    let error: Error?
}

final class SleepAnchoredQueryService {
    private let healthStore: HKHealthStore
    private let sleepType: HKCategoryType
    private let anchorURL: URL

    init(
        healthStore: HKHealthStore,
        sleepType: HKCategoryType,
        anchorURL: URL = FileStore.applicationSupportDirectory.appendingPathComponent("sleep_anchor.data")
    ) {
        self.healthStore = healthStore
        self.sleepType = sleepType
        self.anchorURL = anchorURL
    }

    func fetchUpdates(
        queryTriggeredAt: Date,
        sessionId: UUID?,
        syncSource: String,
        completion: @escaping (AnchoredQueryResult) -> Void
    ) {
        let queryStartedAt = Date()
        let query = HKAnchoredObjectQuery(
            type: sleepType,
            predicate: nil,
            anchor: loadAnchor(),
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samplesOrNil, deletedObjectsOrNil, newAnchor, error in
            let receivedAt = Date()
            if let newAnchor {
                self?.saveAnchor(newAnchor)
            }

            let records = (samplesOrNil ?? [])
                .compactMap { $0 as? HKCategorySample }
                .map {
                    SleepSampleMapper.map(
                        sample: $0,
                        receivedAt: receivedAt,
                        queryTriggeredAt: queryTriggeredAt,
                        sessionId: sessionId,
                        syncSource: syncSource
                    )
                }

            completion(
                AnchoredQueryResult(
                    samples: records,
                    deletedObjectCount: deletedObjectsOrNil?.count ?? 0,
                    queryStartedAt: queryStartedAt,
                    queryFinishedAt: Date(),
                    error: error
                )
            )
        }
        healthStore.execute(query)
    }

    func bootstrapAnchorIfNeeded(completion: @escaping (AnchorBootstrapResult) -> Void) {
        guard !hasAnchor else {
            completion(
                AnchorBootstrapResult(
                    historicalSampleCount: 0,
                    deletedObjectCount: 0,
                    queryStartedAt: Date(),
                    queryFinishedAt: Date(),
                    error: nil
                )
            )
            return
        }

        let queryStartedAt = Date()
        let query = HKAnchoredObjectQuery(
            type: sleepType,
            predicate: nil,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samplesOrNil, deletedObjectsOrNil, newAnchor, error in
            if let newAnchor {
                self?.saveAnchor(newAnchor)
            }

            completion(
                AnchorBootstrapResult(
                    historicalSampleCount: samplesOrNil?.count ?? 0,
                    deletedObjectCount: deletedObjectsOrNil?.count ?? 0,
                    queryStartedAt: queryStartedAt,
                    queryFinishedAt: Date(),
                    error: error
                )
            )
        }
        healthStore.execute(query)
    }

    func resetAnchor() {
        try? FileManager.default.removeItem(at: anchorURL)
    }

    private var hasAnchor: Bool {
        FileManager.default.fileExists(atPath: anchorURL.path)
    }

    private func loadAnchor() -> HKQueryAnchor? {
        guard let data = try? Data(contentsOf: anchorURL) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else {
            return
        }
        try? data.write(to: anchorURL, options: [.atomic])
    }
}
