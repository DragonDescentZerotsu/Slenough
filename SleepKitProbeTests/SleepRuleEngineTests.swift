import Foundation
import Testing
@testable import SleepKitProbe

struct SleepRuleEngineTests {
    @Test func settlingPeriodDoesNotPredictAsleep() {
        var config = SleepRuleConfig.default
        config.settlingMinutes = 10
        config.lowMotionConsecutiveEpochsForSleep = 1
        var engine = SleepRuleEngine(config: config)

        let output = engine.evaluate(input(minute: 5, motionScore: 0.001, burstCount: 0))

        #expect(output.predictedState == .awake)
        #expect(output.estimatedSleepSeconds == 0)
        #expect(output.reason == "settling_period")
    }

    @Test func consecutiveLowMotionPredictsAsleepAndAccumulatesDuration() {
        var config = SleepRuleConfig.default
        config.settlingMinutes = 0
        config.lowMotionConsecutiveEpochsForSleep = 2
        var engine = SleepRuleEngine(config: config)

        _ = engine.evaluate(input(minute: 1, motionScore: 0.001, burstCount: 0))
        let output = engine.evaluate(input(minute: 2, motionScore: 0.001, burstCount: 0))

        #expect(output.predictedState == .asleep)
        #expect(output.estimatedSleepSeconds == 60)
        #expect(output.asleepProbability >= 0.75)
    }

    @Test func highMotionWakesAfterConfiguredEpochs() {
        var config = SleepRuleConfig.default
        config.settlingMinutes = 0
        config.lowMotionConsecutiveEpochsForSleep = 1
        config.highMotionEpochsForAwake = 2
        var engine = SleepRuleEngine(config: config)

        _ = engine.evaluate(input(minute: 1, motionScore: 0.001, burstCount: 0))
        _ = engine.evaluate(input(minute: 2, motionScore: 0.20, burstCount: 3))
        let output = engine.evaluate(input(minute: 3, motionScore: 0.20, burstCount: 3))

        #expect(output.predictedState == .awake)
        #expect(output.reason == "high_motion")
    }

    @Test func manualOverrideWins() {
        var engine = SleepRuleEngine(config: .default)

        let output = engine.evaluate(input(minute: 0, motionScore: 1.0, burstCount: 10, manualOverride: .asleep))

        #expect(output.predictedState == .asleep)
        #expect(output.estimatedSleepSeconds == 60)
        #expect(output.reason == "manual_override")
    }

    private func input(
        minute: Double,
        motionScore: Double,
        burstCount: Int,
        manualOverride: SleepState? = nil
    ) -> SleepRuleInput {
        let start = Date(timeIntervalSince1970: minute * 60)
        return SleepRuleInput(
            epochStart: start,
            epochEnd: start.addingTimeInterval(60),
            motionScore: motionScore,
            motionBurstCount: burstCount,
            heartRateMean: nil,
            heartRateLatest: nil,
            heartRateBaseline: nil,
            minutesSinceSessionStart: minute,
            manualOverride: manualOverride
        )
    }
}
