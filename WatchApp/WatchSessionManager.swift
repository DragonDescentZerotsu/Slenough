import Combine
import Foundation
import SwiftUI
import WatchKit

final class WatchSessionManager: NSObject, ObservableObject {
    @Published private(set) var state: ProbeSessionState = .idle
    @Published private(set) var predictedState: SleepState = .unknown
    @Published private(set) var estimatedSleepSeconds: TimeInterval = 0
    @Published private(set) var latestHeartRate: Double?
    @Published private(set) var latestMotionScore: Double = 0
    @Published private(set) var batteryLevel: Double?

    private var sessionId: UUID?
    private var sessionStartedAt: Date?
    private var epochIndex = 0
    private var config = SleepRuleConfig.default
    private var ruleEngine = SleepRuleEngine()
    private var manualOverride: SleepState?
    private var baselineHeartRates: [Double] = []

    private let motionSampler = MotionSampler()
    private let heartRateSampler = HeartRateSampler()
    private let logStore = WatchLocalLogStore()
    private let connectivity = WatchConnectivitySender()
    private var extendedRuntimeSession: WKExtendedRuntimeSession?

    override init() {
        super.init()
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        heartRateSampler.onHeartRateUpdate = { [weak self] heartRate in
            DispatchQueue.main.async {
                self?.latestHeartRate = heartRate
                self?.captureBaselineHeartRate(heartRate)
            }
        }
        connectivity.onConfigReceived = { [weak self] config in
            self?.applyConfig(config)
        }
        connectivity.onSyncRequested = { [weak self] in
            self?.syncNow()
        }
    }

    func startSession(goalSeconds: TimeInterval, maxEndTime: Date? = nil) {
        guard state != .running && state != .starting else { return }
        let newSessionId = UUID()
        sessionId = newSessionId
        sessionStartedAt = Date()
        epochIndex = 0
        config.sleepGoalSeconds = goalSeconds
        config.latestWakeTime = maxEndTime
        ruleEngine.reset(config: config)
        manualOverride = nil
        baselineHeartRates.removeAll()
        predictedState = .unknown
        estimatedSleepSeconds = 0
        state = .starting

        recordEvent("session_started", message: "goalSeconds=\(Int(goalSeconds))")
        if config.extendedRuntimeEnabled {
            startExtendedRuntime()
        } else {
            recordEvent("extended_runtime_skipped", message: "disabled_by_config")
        }

        if config.heartRateSamplingEnabled {
            heartRateSampler.requestReadAuthorization { [weak self] result in
                DispatchQueue.main.async {
                    if case .failure(let error) = result {
                        self?.recordEvent("heart_rate_failed", message: error.localizedDescription)
                    } else {
                        self?.recordEvent("heart_rate_started", message: "passive_healthkit_epoch_query")
                    }
                }
            }
        } else {
            recordEvent("heart_rate_skipped", message: "disabled_by_config")
        }

        motionSampler.start(epochSeconds: config.epochSeconds, sampleHz: config.motionSampleHz) { [weak self] epochStats in
            DispatchQueue.main.async {
                self?.handleMotionEpoch(epochStats)
            }
        }
        recordEvent("motion_started", message: "epochSeconds=\(Int(config.epochSeconds)) sampleHz=\(config.motionSampleHz)")
        state = .running
    }

    func stopSession(reason: String) {
        guard state == .running || state == .starting else { return }
        state = .stopping
        motionSampler.stop()
        heartRateSampler.stop()
        extendedRuntimeSession?.invalidate()
        recordEvent("motion_stopped", message: reason)
        recordEvent("heart_rate_stopped", message: reason)
        recordEvent("session_stopped", message: reason)
        state = .stopped
        sessionId = nil
        sessionStartedAt = nil
    }

    func pauseSession(reason: String) {
        guard state == .running else { return }
        motionSampler.stop()
        recordEvent("session_paused", message: reason)
        state = .stopped
    }

    func resumeSession() {
        guard state == .stopped, sessionId != nil else { return }
        motionSampler.start(epochSeconds: config.epochSeconds, sampleHz: config.motionSampleHz) { [weak self] epochStats in
            DispatchQueue.main.async {
                self?.handleMotionEpoch(epochStats)
            }
        }
        recordEvent("session_resumed", message: nil)
        state = .running
    }

    func markAwake() {
        manualOverride = .awake
        recordEvent("manual_awake_mark", message: nil)
    }

    func markAsleep() {
        manualOverride = .asleep
        recordEvent("manual_asleep_mark", message: nil)
    }

    func syncNow() {
        connectivity.flushQueuedUserInfo()
        recordEvent("connectivity_sync_requested", message: nil)
    }

    private func applyConfig(_ newConfig: SleepRuleConfig) {
        config = newConfig
        if state == .idle || state == .stopped {
            ruleEngine.reset(config: newConfig)
        }
        recordEvent("config_received", message: "epochSeconds=\(Int(newConfig.epochSeconds)) goalSeconds=\(Int(newConfig.sleepGoalSeconds))")
    }

    private func handleMotionEpoch(_ stats: MotionEpochStats) {
        guard let sessionId, let sessionStartedAt else { return }

        batteryLevel = Double(WKInterfaceDevice.current().batteryLevel)
        latestMotionScore = stats.motionScore

        if config.heartRateSamplingEnabled {
            heartRateSampler.snapshot(from: stats.startDate, to: stats.endDate) { [weak self] snapshot in
                DispatchQueue.main.async {
                    self?.finishEpoch(stats, heartRateSnapshot: snapshot, sessionId: sessionId, sessionStartedAt: sessionStartedAt)
                }
            }
        } else {
            finishEpoch(stats, heartRateSnapshot: HeartRateSnapshot(mean: nil, latest: nil, sampleCount: 0), sessionId: sessionId, sessionStartedAt: sessionStartedAt)
        }
    }

    private func finishEpoch(_ stats: MotionEpochStats, heartRateSnapshot: HeartRateSnapshot, sessionId: UUID, sessionStartedAt: Date) {
        latestHeartRate = heartRateSnapshot.latest
        if let latest = heartRateSnapshot.latest {
            captureBaselineHeartRate(latest)
        }

        let input = SleepRuleInput(
            epochStart: stats.startDate,
            epochEnd: stats.endDate,
            motionScore: stats.motionScore,
            motionBurstCount: stats.motionBurstCount,
            heartRateMean: heartRateSnapshot.mean,
            heartRateLatest: heartRateSnapshot.latest,
            heartRateBaseline: currentHeartRateBaseline,
            minutesSinceSessionStart: stats.endDate.timeIntervalSince(sessionStartedAt) / 60,
            manualOverride: manualOverride
        )
        let output = ruleEngine.evaluate(input)
        manualOverride = nil
        predictedState = output.predictedState
        estimatedSleepSeconds = output.estimatedSleepSeconds

        let epoch = WatchEpoch(
            id: UUID(),
            sessionId: sessionId,
            epochIndex: epochIndex,
            epochStart: stats.startDate,
            epochEnd: stats.endDate,
            watchTimestamp: Date(),
            sampleCount: stats.sampleCount,
            accelMeanX: stats.accelMeanX,
            accelMeanY: stats.accelMeanY,
            accelMeanZ: stats.accelMeanZ,
            accelStdX: stats.accelStdX,
            accelStdY: stats.accelStdY,
            accelStdZ: stats.accelStdZ,
            accelMagnitudeMean: stats.accelMagnitudeMean,
            accelMagnitudeStd: stats.accelMagnitudeStd,
            motionScore: stats.motionScore,
            motionBurstCount: stats.motionBurstCount,
            isMotionDataAvailable: stats.isMotionDataAvailable,
            heartRateMean: heartRateSnapshot.mean,
            heartRateLatest: heartRateSnapshot.latest,
            heartRateSampleCount: heartRateSnapshot.sampleCount,
            heartRateAvailable: heartRateSnapshot.sampleCount > 0,
            batteryLevel: batteryLevel,
            isCharging: WKInterfaceDevice.current().batteryState == .charging || WKInterfaceDevice.current().batteryState == .full,
            predictedState: output.predictedState,
            asleepProbability: output.asleepProbability,
            estimatedSleepSeconds: output.estimatedSleepSeconds,
            algorithmVersion: SleepRuleEngine.algorithmVersion,
            notes: output.reason
        )
        logStore.appendEpoch(epoch)

        let summary = EpochSummary(
            sessionId: sessionId,
            epochIndex: epochIndex,
            startDate: stats.startDate,
            endDate: stats.endDate,
            motionScore: stats.motionScore,
            accelMagnitudeMean: stats.accelMagnitudeMean,
            accelMagnitudeStd: stats.accelMagnitudeStd,
            heartRateMean: heartRateSnapshot.mean,
            heartRateLatest: heartRateSnapshot.latest,
            heartRateSampleCount: heartRateSnapshot.sampleCount,
            heartRateAvailable: heartRateSnapshot.sampleCount > 0,
            batteryLevel: batteryLevel,
            predictedState: output.predictedState,
            asleepProbability: output.asleepProbability,
            estimatedSleepSeconds: output.estimatedSleepSeconds,
            algorithmVersion: SleepRuleEngine.algorithmVersion
        )
        connectivity.send(summary: summary)
        recordEvent("connectivity_sent", message: "epochIndex=\(epochIndex)")
        epochIndex += 1
    }

    private func startExtendedRuntime() {
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        extendedRuntimeSession = session
        session.start()
    }

    private func recordEvent(_ type: String, message: String?) {
        let event = WatchEventRecord(id: UUID(), sessionId: sessionId, timestamp: Date(), type: type, message: message)
        logStore.appendEvent(event)
    }

    private func captureBaselineHeartRate(_ heartRate: Double) {
        guard baselineHeartRates.count < 10 else { return }
        baselineHeartRates.append(heartRate)
    }

    private var currentHeartRateBaseline: Double? {
        guard !baselineHeartRates.isEmpty else { return nil }
        return baselineHeartRates.reduce(0, +) / Double(baselineHeartRates.count)
    }
}

extension WatchSessionManager: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        recordEvent("extended_runtime_started", message: nil)
    }

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        recordEvent("extended_runtime_will_expire", message: nil)
    }

    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        recordEvent("extended_runtime_invalidated", message: "reason=\(reason.rawValue) error=\(error?.localizedDescription ?? "")")
    }
}
