# Phase 1 HealthKit Findings

## Experiment Result

A full-night device test showed that the iOS app can read HealthKit `sleepAnalysis` samples and that `HKObserverQuery` / `HKAnchoredObjectQuery` can detect changes after new samples enter the HealthKit store.

The critical finding is that Apple Watch / Apple Health did not write sleep-stage samples to HealthKit in real time during the night. After waking, manually refreshing this app still did not show new sleep samples until Apple Health was opened and the official sleep view appeared. After that, HealthKit updates became visible and the observer path fired.

## Conclusion

HealthKit `sleepAnalysis` is useful for post-hoc evaluation, but it is not a reliable real-time source for a "wake me after enough real sleep" alarm.

## Product Impact

Do not keep investing in more frequent `HKSampleQuery` or anchored-query polling as the real-time trigger. Do not use private APIs, Health app automation, URL-scheme tricks, or any non-public sleep-stage API.

Phase 2 moves the real-time logic to Apple Watch:

- collect motion and heart-rate availability during a user-started session
- estimate awake/asleep locally on Watch
- accumulate estimated sleep seconds locally on Watch
- sync low-frequency summaries to iPhone for display, export, and next-day comparison

HealthKit remains in the project only for next-day official sleep comparison and algorithm calibration.

## Current Implementation Impact

The app now keeps Phase 1 screens and exports for post-hoc validation, but active development has moved to Phase 2:

- Watch records 60-second sensor epochs during a user-started session.
- Motion sampling defaults to 1 Hz.
- Heart-rate collection defaults to passive HealthKit epoch queries, not workout-level live HR.
- iPhone receives Watch summaries and exports `watch_epoch_summaries.csv` / `watch_events.csv`.

The remaining comparison step is still manual: export Watch CSVs, refresh/export HealthKit sleep samples after Apple Health has produced official sleep data, then compare the timelines outside the app.
