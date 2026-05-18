import CoreMotion
import Foundation

struct MotionEpochStats {
    let startDate: Date
    let endDate: Date
    let sampleCount: Int
    let accelMeanX: Double?
    let accelMeanY: Double?
    let accelMeanZ: Double?
    let accelStdX: Double?
    let accelStdY: Double?
    let accelStdZ: Double?
    let accelMagnitudeMean: Double?
    let accelMagnitudeStd: Double?
    let motionScore: Double
    let motionBurstCount: Int
    let isMotionDataAvailable: Bool
}

final class MotionSampler {
    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var epochStart = Date()
    private var samples: [(x: Double, y: Double, z: Double, magnitude: Double)] = []
    private var timer: Timer?
    private var onEpoch: ((MotionEpochStats) -> Void)?

    func start(epochSeconds: TimeInterval, sampleHz: Double = 10, onEpoch: @escaping (MotionEpochStats) -> Void) {
        stop()
        self.onEpoch = onEpoch
        epochStart = Date()
        samples.removeAll()
        queue.name = "SleepKitProbe.MotionSampler"

        guard motionManager.isAccelerometerAvailable else {
            timer = Timer.scheduledTimer(withTimeInterval: epochSeconds, repeats: true) { [weak self] _ in
                self?.finishEpoch()
            }
            return
        }

        motionManager.accelerometerUpdateInterval = 1 / max(sampleHz, 1)
        motionManager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let acceleration = data?.acceleration else { return }
            let magnitude = sqrt(
                acceleration.x * acceleration.x +
                acceleration.y * acceleration.y +
                acceleration.z * acceleration.z
            )
            self.lock.lock()
            self.samples.append((acceleration.x, acceleration.y, acceleration.z, magnitude))
            self.lock.unlock()
        }

        timer = Timer.scheduledTimer(withTimeInterval: epochSeconds, repeats: true) { [weak self] _ in
            self?.finishEpoch()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if motionManager.isAccelerometerActive {
            motionManager.stopAccelerometerUpdates()
        }
        lock.lock()
        samples.removeAll()
        lock.unlock()
    }

    private func finishEpoch() {
        let endDate = Date()
        lock.lock()
        let snapshot = samples
        samples.removeAll()
        lock.unlock()

        let stats = Self.stats(from: snapshot, startDate: epochStart, endDate: endDate)
        epochStart = endDate
        onEpoch?(stats)
    }

    static func stats(
        from samples: [(x: Double, y: Double, z: Double, magnitude: Double)],
        startDate: Date,
        endDate: Date
    ) -> MotionEpochStats {
        guard !samples.isEmpty else {
            return MotionEpochStats(
                startDate: startDate,
                endDate: endDate,
                sampleCount: 0,
                accelMeanX: nil,
                accelMeanY: nil,
                accelMeanZ: nil,
                accelStdX: nil,
                accelStdY: nil,
                accelStdZ: nil,
                accelMagnitudeMean: nil,
                accelMagnitudeStd: nil,
                motionScore: 0,
                motionBurstCount: 0,
                isMotionDataAvailable: false
            )
        }

        let xs = samples.map { $0.x }
        let ys = samples.map { $0.y }
        let zs = samples.map { $0.z }
        let magnitudes = samples.map { $0.magnitude }
        let magnitudeMean = mean(magnitudes)
        let magnitudeStd = standardDeviation(magnitudes, mean: magnitudeMean)
        // Phase 2 baseline motion score: standard deviation of acceleration magnitude in g units.
        let motionScore = magnitudeStd
        let burstCount = magnitudes.filter { abs($0 - 1.0) > 0.20 }.count

        return MotionEpochStats(
            startDate: startDate,
            endDate: endDate,
            sampleCount: samples.count,
            accelMeanX: mean(xs),
            accelMeanY: mean(ys),
            accelMeanZ: mean(zs),
            accelStdX: standardDeviation(xs, mean: mean(xs)),
            accelStdY: standardDeviation(ys, mean: mean(ys)),
            accelStdZ: standardDeviation(zs, mean: mean(zs)),
            accelMagnitudeMean: magnitudeMean,
            accelMagnitudeStd: magnitudeStd,
            motionScore: motionScore,
            motionBurstCount: burstCount,
            isMotionDataAvailable: true
        )
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func standardDeviation(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance)
    }
}
