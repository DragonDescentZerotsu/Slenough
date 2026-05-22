# Phase 2 Watch Probe Protocol

This is a research probe, not a reliable alarm. During every test, set a normal system alarm as backup.

## Daytime Short Test

1. Install the iOS app and Watch app from Xcode.
2. Open the Watch app and tap `Start Session`.
3. Keep the watch wrist still for 10-15 minutes.
4. Move the wrist for 5 minutes.
5. Tap `Stop Session`.
6. Open the iPhone app `Watch` tab.
7. Tap `Request Watch Sync` if needed.
8. Tap `Export Epoch CSV`.

Expected result:

- `watch_epoch_summaries.csv` has consecutive epochs.
- Still periods have lower `motion_score`.
- Movement periods have a higher `motion_score`.
- `predicted_state`, `asleep_probability`, and `estimated_sleep_seconds` are populated.
- Heart-rate fields may be empty if watchOS did not save a passive HR sample during that epoch; that should not crash the session.

## Overnight Test

1. Charge the Watch enough for overnight use.
2. Set a normal system alarm as backup.
3. Open the Watch app before sleep.
4. Tap `Start Session`.
5. Sleep normally while wearing the Watch.
6. On waking, tap `Stop Session` on Watch.
7. Open the iPhone app and tap `Request Watch Sync`.
8. Export Watch epoch CSV and Watch event CSV.
9. Open Apple Health so official sleepAnalysis appears.
10. Return to this app and use Phase 1 HealthKit refresh/export for post-hoc comparison.

## Interpretation

For Phase 2, the key questions are:

- Did Watch produce epochs across most of the night?
- Are missing data periods visible instead of silent?
- Does motion score separate stillness from movement?
- How often does passive HR appear? Inspect `heart_rate_available` and `heart_rate_sample_count`.
- Is battery drain acceptable with 0.2 Hz motion, 300-second epochs, and passive HR, compared with earlier high-frequency runs?
- Does estimated sleep duration roughly track Apple Health after the fact?
- Does battery drain improve after switching to the low-power profile while preserving enough accuracy for overnight sleep-duration estimation?

Do not use HealthKit sleepAnalysis as a real-time trigger.
