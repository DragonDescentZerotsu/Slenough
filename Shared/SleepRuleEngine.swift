import Foundation

struct SleepRuleEngine {
    static let algorithmVersion = "motion-baseline-v1"

    private(set) var config: SleepRuleConfig
    private(set) var consecutiveLowMotionEpochs = 0
    private(set) var consecutiveHighMotionEpochs = 0
    private(set) var estimatedSleepSeconds: TimeInterval = 0
    private(set) var previousState: SleepState = .unknown

    init(config: SleepRuleConfig = .default) {
        self.config = config
    }

    mutating func reset(config: SleepRuleConfig? = nil) {
        if let config {
            self.config = config
        }
        consecutiveLowMotionEpochs = 0
        consecutiveHighMotionEpochs = 0
        estimatedSleepSeconds = 0
        previousState = .unknown
    }

    mutating func evaluate(_ input: SleepRuleInput) -> SleepRuleOutput {
        if let manualOverride = input.manualOverride {
            return apply(state: manualOverride, probability: manualOverride == .asleep ? 1.0 : 0.0, input: input, reason: "manual_override")
        }

        if input.motionScore <= config.lowMotionThreshold && input.motionBurstCount == 0 {
            consecutiveLowMotionEpochs += 1
        } else {
            consecutiveLowMotionEpochs = 0
        }

        if input.motionScore >= config.highMotionThreshold || input.motionBurstCount >= config.motionBurstThreshold {
            consecutiveHighMotionEpochs += 1
        } else {
            consecutiveHighMotionEpochs = 0
        }

        let heartRateDrop = heartRateDrop(from: input)
        let isSettling = input.minutesSinceSessionStart < Double(config.settlingMinutes)

        let motionProbability = min(1.0, Double(consecutiveLowMotionEpochs) / Double(max(config.lowMotionConsecutiveEpochsForSleep, 1)))
        let heartRateBonus = heartRateDrop >= config.heartRateDropThreshold ? 0.2 : 0
        let asleepProbability = max(0, min(1, motionProbability + heartRateBonus))

        if isSettling {
            return apply(state: .awake, probability: min(asleepProbability, 0.4), input: input, reason: "settling_period")
        }

        if consecutiveHighMotionEpochs >= config.highMotionEpochsForAwake {
            return apply(state: .awake, probability: 0.05, input: input, reason: "high_motion")
        }

        if input.motionBurstCount > 0 && previousState == .asleep {
            return apply(state: .restless, probability: 0.45, input: input, reason: "motion_burst_after_sleep")
        }

        if consecutiveLowMotionEpochs >= config.lowMotionConsecutiveEpochsForSleep {
            let reason = heartRateDrop >= config.heartRateDropThreshold ? "low_motion_heart_rate_drop" : "low_motion"
            return apply(state: .asleep, probability: max(asleepProbability, 0.75), input: input, reason: reason)
        }

        return apply(state: previousState == .asleep ? .restless : .awake, probability: asleepProbability, input: input, reason: "insufficient_sleep_evidence")
    }

    private func heartRateDrop(from input: SleepRuleInput) -> Double {
        guard let baseline = input.heartRateBaseline,
              let latest = input.heartRateMean ?? input.heartRateLatest else {
            return 0
        }
        return baseline - latest
    }

    private mutating func apply(state: SleepState, probability: Double, input: SleepRuleInput, reason: String) -> SleepRuleOutput {
        let duration = max(0, input.epochEnd.timeIntervalSince(input.epochStart))
        if state == .asleep || (state == .restless && config.countRestlessAsSleep) {
            estimatedSleepSeconds += duration
        }
        previousState = state
        return SleepRuleOutput(
            predictedState: state,
            asleepProbability: probability,
            estimatedSleepSeconds: estimatedSleepSeconds,
            reason: reason
        )
    }
}
