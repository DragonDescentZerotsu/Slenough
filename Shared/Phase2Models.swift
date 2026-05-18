import Foundation

enum SleepState: String, Codable, CaseIterable, Identifiable {
    case unknown
    case awake
    case asleep
    case restless

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .awake: return "Awake"
        case .asleep: return "Asleep"
        case .restless: return "Restless"
        }
    }
}

enum ProbeSessionState: Equatable {
    case idle
    case starting
    case running
    case stopping
    case stopped
    case failed(String)

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .starting: return "Starting"
        case .running: return "Running"
        case .stopping: return "Stopping"
        case .stopped: return "Stopped"
        case .failed(let message): return "Error: \(message)"
        }
    }
}

struct SensorAvailability: Codable, Equatable {
    var motionAvailable: Bool
    var heartRateAvailable: Bool
    var extendedRuntimeAvailable: Bool
}

struct SleepRuleConfig: Codable, Equatable {
    var epochSeconds: TimeInterval
    var settlingMinutes: Int
    var lowMotionConsecutiveEpochsForSleep: Int
    var highMotionEpochsForAwake: Int
    var countRestlessAsSleep: Bool
    var lowMotionThreshold: Double
    var highMotionThreshold: Double
    var motionBurstThreshold: Int
    var heartRateDropThreshold: Double
    var sleepGoalSeconds: TimeInterval
    var latestWakeTime: Date?
    var fallbackAlarmTime: Date?

    static let `default` = SleepRuleConfig(
        epochSeconds: 60,
        settlingMinutes: 10,
        lowMotionConsecutiveEpochsForSleep: 10,
        highMotionEpochsForAwake: 2,
        countRestlessAsSleep: false,
        lowMotionThreshold: 0.035,
        highMotionThreshold: 0.12,
        motionBurstThreshold: 2,
        heartRateDropThreshold: 5,
        sleepGoalSeconds: 7 * 60 * 60,
        latestWakeTime: nil,
        fallbackAlarmTime: nil
    )
}

struct SleepRuleInput {
    let epochStart: Date
    let epochEnd: Date
    let motionScore: Double
    let motionBurstCount: Int
    let heartRateMean: Double?
    let heartRateLatest: Double?
    let heartRateBaseline: Double?
    let minutesSinceSessionStart: Double
    let manualOverride: SleepState?
}

struct SleepRuleOutput: Equatable {
    let predictedState: SleepState
    let asleepProbability: Double
    let estimatedSleepSeconds: TimeInterval
    let reason: String
}

struct EpochSummary: Codable, Identifiable, Equatable {
    let id: UUID
    let sessionId: UUID
    let epochIndex: Int
    let startDate: Date
    let endDate: Date
    let motionScore: Double
    let accelMagnitudeMean: Double?
    let accelMagnitudeStd: Double?
    let heartRateMean: Double?
    let heartRateLatest: Double?
    let heartRateSampleCount: Int
    let heartRateAvailable: Bool
    let batteryLevel: Double?
    let predictedState: SleepState
    let asleepProbability: Double
    let estimatedSleepSeconds: TimeInterval
    let algorithmVersion: String

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        epochIndex: Int,
        startDate: Date,
        endDate: Date,
        motionScore: Double,
        accelMagnitudeMean: Double?,
        accelMagnitudeStd: Double?,
        heartRateMean: Double?,
        heartRateLatest: Double?,
        heartRateSampleCount: Int,
        heartRateAvailable: Bool,
        batteryLevel: Double?,
        predictedState: SleepState,
        asleepProbability: Double,
        estimatedSleepSeconds: TimeInterval,
        algorithmVersion: String
    ) {
        self.id = id
        self.sessionId = sessionId
        self.epochIndex = epochIndex
        self.startDate = startDate
        self.endDate = endDate
        self.motionScore = motionScore
        self.accelMagnitudeMean = accelMagnitudeMean
        self.accelMagnitudeStd = accelMagnitudeStd
        self.heartRateMean = heartRateMean
        self.heartRateLatest = heartRateLatest
        self.heartRateSampleCount = heartRateSampleCount
        self.heartRateAvailable = heartRateAvailable
        self.batteryLevel = batteryLevel
        self.predictedState = predictedState
        self.asleepProbability = asleepProbability
        self.estimatedSleepSeconds = estimatedSleepSeconds
        self.algorithmVersion = algorithmVersion
    }
}

struct WatchEpoch: Codable, Identifiable, Equatable {
    let id: UUID
    let sessionId: UUID
    let epochIndex: Int
    let epochStart: Date
    let epochEnd: Date
    let watchTimestamp: Date
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
    let heartRateMean: Double?
    let heartRateLatest: Double?
    let heartRateSampleCount: Int
    let heartRateAvailable: Bool
    let batteryLevel: Double?
    let isCharging: Bool?
    let predictedState: SleepState
    let asleepProbability: Double
    let estimatedSleepSeconds: TimeInterval
    let algorithmVersion: String
    let notes: String?
}

struct WatchEventRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let sessionId: UUID?
    let timestamp: Date
    let type: String
    let message: String?
}
