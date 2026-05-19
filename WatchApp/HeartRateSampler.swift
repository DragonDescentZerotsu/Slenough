import Foundation
import HealthKit

struct HeartRateSnapshot {
    let mean: Double?
    let latest: Double?
    let sampleCount: Int
}

final class HeartRateSampler: NSObject {
    var onHeartRateUpdate: ((Double) -> Void)?

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var values: [Double] = []

    func requestReadAuthorization(completion: @escaping (Result<Void, Error>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            completion(.failure(HeartRateError.healthDataUnavailable))
            return
        }

        healthStore.requestAuthorization(toShare: [], read: [heartRateType]) { success, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard success else {
                completion(.failure(HeartRateError.authorizationDenied))
                return
            }
            completion(.success(()))
        }
    }

    func snapshot(from startDate: Date, to endDate: Date, completion: @escaping (HeartRateSnapshot) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            completion(HeartRateSnapshot(mean: nil, latest: nil, sampleCount: 0))
            return
        }

        // Passive low-power path: read heart-rate samples watchOS already saved for this epoch.
        // This does not force the optical sensor to sample once per minute.
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
            let unit = HKUnit.count().unitDivided(by: .minute())
            let values = (samples as? [HKQuantitySample] ?? []).map { sample in
                sample.quantity.doubleValue(for: unit)
            }
            guard !values.isEmpty else {
                completion(HeartRateSnapshot(mean: nil, latest: nil, sampleCount: 0))
                return
            }
            completion(
                HeartRateSnapshot(
                    mean: values.reduce(0, +) / Double(values.count),
                    latest: values.last,
                    sampleCount: values.count
                )
            )
        }
        healthStore.execute(query)
    }

    func requestAuthorizationAndStart(completion: @escaping (Result<Void, Error>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            completion(.failure(HeartRateError.healthDataUnavailable))
            return
        }

        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        healthStore.requestAuthorization(toShare: shareTypes, read: [heartRateType]) { [weak self] success, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard success else {
                completion(.failure(HeartRateError.authorizationDenied))
                return
            }
            DispatchQueue.main.async {
                do {
                    try self?.startWorkoutCollection()
                    completion(.success(()))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    func stop() {
        workoutBuilder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.workoutBuilder?.finishWorkout { _, _ in }
        }
        workoutSession?.end()
        workoutSession = nil
        workoutBuilder = nil
        values.removeAll()
    }

    func snapshotAndReset() -> HeartRateSnapshot {
        let snapshot = values
        values.removeAll()
        guard !snapshot.isEmpty else {
            return HeartRateSnapshot(mean: nil, latest: nil, sampleCount: 0)
        }
        return HeartRateSnapshot(
            mean: snapshot.reduce(0, +) / Double(snapshot.count),
            latest: snapshot.last,
            sampleCount: snapshot.count
        )
    }

    private func startWorkoutCollection() throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .mindAndBody
        configuration.locationType = .unknown

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self
        workoutSession = session
        workoutBuilder = builder

        session.startActivity(with: Date())
        builder.beginCollection(withStart: Date()) { _, _ in }
    }
}

extension HeartRateSampler: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

extension HeartRateSampler: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(heartRateType),
              let statistics = workoutBuilder.statistics(for: heartRateType),
              let quantity = statistics.mostRecentQuantity() else {
            return
        }

        let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        values.append(bpm)
        onHeartRateUpdate?(bpm)
    }
}

enum HeartRateError: LocalizedError {
    case healthDataUnavailable
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable: return "Health data is unavailable on this Watch."
        case .authorizationDenied: return "Heart rate authorization was denied."
        }
    }
}
