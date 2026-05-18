# SleepKitProbe Phase 2: Watch-side Sensor Probe

Phase 2 verifies Apple Watch-side motion and heart-rate collection for a future "sleep enough, then wake" alarm. This is a research probe, not a reliable alarm. During tests, set a normal system alarm as backup.

## What Changed After Phase 1

Phase 1 showed that Apple Health `sleepAnalysis` is not written in time for real-time wake decisions. HealthKit remains useful for next-day comparison, but Phase 2 estimates awake/asleep on Watch from user-started sensor collection.

## Install

1. Open `SleepKitProbe.xcodeproj` in Xcode.
2. Select your development team for both `SleepKitProbe` and `SleepKitProbe Watch App`.
3. Confirm capabilities:
   - iOS: HealthKit.
   - Watch: HealthKit.
4. Build/run on a real iPhone paired to a real Apple Watch.
5. Grant HealthKit sleep permission on iPhone and heart-rate/workout permission on Watch when prompted.

Simulator cannot validate real overnight Watch sensor behavior.

## Xcode Schemes and Preview

Use these schemes from the dropdown next to Xcode's Run button:

- `SleepKitProbe`: install and run the iPhone app, with the Watch app embedded.
- `SleepKitProbe Watch App`: run or preview the Watch app directly.

To preview the Watch UI:

1. Open `WatchApp/WatchContentView.swift`.
2. Select the `SleepKitProbe Watch App` scheme.
3. Select an Apple Watch simulator destination.
4. Open Canvas and resume the preview.

To install on real devices:

1. Select the `SleepKitProbe` scheme.
2. Select your paired iPhone + Apple Watch destination.
3. Run from Xcode.

If Watch installation fails with a generic "could not be installed" message:

- Delete old copies from both iPhone and Watch.
- Run `Product > Clean Build Folder`.
- Confirm both targets use the same development team.
- Confirm the Watch target deployment target is not higher than your watchOS version.
- Confirm the Watch app Info.plist includes `WKCompanionAppBundleIdentifier = Tianang.SleepKitProbe`.

## Daytime Functional Test

1. Open the Watch app.
2. Tap `Start Session`.
3. Keep the wrist still for 5 minutes.
4. Move the wrist for 1 minute.
5. Tap `Stop Session`.
6. Open the iPhone app and go to the `Watch` tab.
7. Tap `Request Watch Sync` if needed.
8. Tap `Export Epoch CSV`.

Pass criteria:

- `watch_epoch_summaries.csv` contains consecutive epochs.
- Still periods have lower `motion_score`.
- Moving periods have higher `motion_score`.
- The app does not crash if heart rate is unavailable.
- `predicted_state`, `asleep_probability`, and `estimated_sleep_seconds` are populated.

## Overnight Test

1. Charge the Watch enough for overnight use.
2. Set a normal system alarm as backup.
3. Open the Watch app before sleep.
4. Tap `Start Session`.
5. Sleep normally while wearing the Watch.
6. Tap `Stop Session` after waking.
7. Export Watch epoch CSV from the iPhone `Watch` tab.
8. Open Apple Health so official sleep data appears.
9. Use the existing Phase 1 HealthKit refresh/export flow for next-day comparison.

## Watch App Controls

- `Start Session`: begins motion sampling, heart-rate collection attempt, local Watch logging, and epoch summary sync.
- `Stop Session`: stops samplers and records session stop events.
- `Mark Awake`: adds a one-epoch manual awake override for debugging.
- `Mark Asleep`: adds a one-epoch manual asleep override for debugging.
- `Export/Sync Now`: requests WatchConnectivity to flush queued user info to iPhone.

## iPhone Watch Tab

- `Send Goal to Watch`: sends the current default `SleepRuleConfig`.
- `Request Watch Sync`: asks the Watch app to flush pending summaries when reachable.
- `Export Epoch CSV`: exports `watch_epoch_summaries.csv`.
- `Export Watch Event CSV`: exports `watch_events.csv`.
- `Clear iPhone Watch Logs`: clears Watch summaries already received by iPhone. It does not clear Watch local logs.

## CSV Fields to Inspect

`watch_epoch_summaries.csv`:

- `epoch_index`: should increase across the session.
- `start_date` / `end_date`: epoch time window.
- `motion_score`: current baseline is acceleration magnitude standard deviation.
- `heart_rate_available`, `heart_rate_latest`, `heart_rate_sample_count`: heart-rate availability.
- `battery_level`: Watch battery at epoch time.
- `predicted_state`: `unknown`, `awake`, `asleep`, or `restless`.
- `asleep_probability`: baseline rule confidence from `0.0` to `1.0`.
- `estimated_sleep_seconds`: cumulative estimated sleep.
- `algorithm_version`: current rule engine version.

`watch_events.csv`:

- session lifecycle events
- sampler start/stop events
- extended runtime events
- connectivity events
- manual mark events

## Motion Score

Current definition:

```text
motion_score = accelMagnitudeStd
```

This is the standard deviation of `sqrt(x^2 + y^2 + z^2)` in one epoch, using acceleration in approximate `g` units.

Rough starting interpretation:

- `0.000 - 0.015`: very still.
- `0.015 - 0.035`: light movement, often sleep-compatible.
- `0.035 - 0.120`: noticeable movement or turning.
- `> 0.120`: strong movement, often awake/restless.

The default rule uses:

```text
lowMotionThreshold = 0.035
highMotionThreshold = 0.12
```

These are baseline thresholds for data collection, not final product values.

## Current Limits

- The rule engine is a motion-first baseline, not a medical sleep model.
- Heart-rate collection uses `HKWorkoutSession`, which can affect Activity rings.
- Extended runtime availability is recorded but system behavior still depends on watchOS policy.
- Watch logs are saved locally on Watch; iPhone currently receives low-frequency epoch summaries.
- HealthKit sleepAnalysis is post-hoc evaluation only, never the real-time trigger.
