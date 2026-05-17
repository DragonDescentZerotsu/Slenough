import Foundation
import HealthKit

enum SleepSampleMapper {
    static func valueName(rawValue: Int) -> String {
        switch rawValue {
        case HKCategoryValueSleepAnalysis.inBed.rawValue:
            return "inBed"
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            return "asleepUnspecified"
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            return "awake"
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
            return "asleepCore"
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            return "asleepDeep"
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            return "asleepREM"
        default:
            return "unknown(\(rawValue))"
        }
    }

    static func map(
        sample: HKCategorySample,
        receivedAt: Date,
        queryTriggeredAt: Date?,
        sessionId: UUID?,
        syncSource: String
    ) -> SleepSampleRecord {
        SleepSampleRecord(
            sessionId: sessionId,
            sampleUUID: sample.uuid,
            receivedAt: receivedAt,
            queryTriggeredAt: queryTriggeredAt,
            sampleStartDate: sample.startDate,
            sampleEndDate: sample.endDate,
            durationSeconds: sample.endDate.timeIntervalSince(sample.startDate),
            valueRaw: sample.value,
            valueName: valueName(rawValue: sample.value),
            sourceName: sample.sourceRevision.source.name,
            sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
            deviceName: sample.device?.name,
            metadataDescription: metadataDescription(sample.metadata),
            syncSource: syncSource
        )
    }

    private static func metadataDescription(_ metadata: [String: Any]?) -> String? {
        guard let metadata, !metadata.isEmpty else { return nil }
        return metadata.keys.sorted().map { key in
            "\(key)=\(String(describing: metadata[key] ?? ""))"
        }.joined(separator: "; ")
    }
}
