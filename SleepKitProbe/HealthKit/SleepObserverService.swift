import Foundation
import HealthKit

final class SleepObserverService {
    private let healthStore: HKHealthStore
    private let sleepType: HKCategoryType
    private var observerQuery: HKObserverQuery?

    init(healthStore: HKHealthStore, sleepType: HKCategoryType) {
        self.healthStore = healthStore
        self.sleepType = sleepType
    }

    func start(onChange: @escaping (_ triggeredAt: Date, _ error: Error?, _ completion: @escaping () -> Void) -> Void) {
        stop()

        // HKObserverQuery only tells us that the HealthKit store changed. The anchored
        // query does the actual incremental read and records exactly what arrived.
        let query = HKObserverQuery(sampleType: sleepType, predicate: nil) { _, completionHandler, error in
            onChange(Date(), error) {
                completionHandler()
            }
        }
        observerQuery = query
        healthStore.execute(query)
    }

    func stop() {
        if let observerQuery {
            healthStore.stop(observerQuery)
        }
        observerQuery = nil
    }
}
