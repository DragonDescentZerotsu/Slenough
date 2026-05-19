# SleepKitProbe

SleepKitProbe is a local-only iPhone + Apple Watch research app for validating a future "sleep enough, then wake" alarm.

Current focus: **Phase 2 Watch-side Sensor Probe**. The Watch app records 1 Hz motion epochs, passive per-epoch heart-rate availability, and a baseline awake/asleep estimate during a user-started session. The iPhone app receives low-frequency summaries, displays the latest state, and exports CSV logs.

This is not a reliable alarm. During every test, set a normal system alarm as backup.

## Current Implementation Status

Completed on branch `custom-asleep`:

- Phase 1 HealthKit `sleepAnalysis` real-time validation and CSV/JSONL export.
- watchOS app target with start/stop session UI.
- 60-second Watch epochs with 1 Hz Core Motion sampling by default.
- Passive per-epoch HealthKit heart-rate lookup. This reads samples watchOS already saved; it does not force a heart-rate measurement every minute.
- Motion-first baseline sleep/wake rule engine.
- Watch local event/epoch logging plus WatchConnectivity summary sync to iPhone.
- iPhone Watch tab with connection diagnostics, latest epoch display, sync request, and Watch CSV export.
- Duplicate epoch filtering on iPhone exports.

Not completed yet:

- Automatic smart-alarm wake/vibration behavior.
- Full post-hoc comparison report between Watch predictions and Apple sleepAnalysis.
- Open-source model integration or Core ML inference.
- Product UI, App Store preparation, cloud sync, or accounts.

## Project Layout

```text
SleepKitProbe.xcodeproj
SleepKitProbe/        iPhone SwiftUI app, HealthKit post-hoc sleepAnalysis, Watch sync UI
WatchApp/             watchOS SwiftUI app, sensor session, 1 Hz motion and passive HR queries
Shared/               shared Phase 2 models, rule engine, CSV encoder
SleepKitProbeTests/   unit tests
Docs/                 experiment notes and protocols
```

## Xcode Schemes

- `SleepKitProbe`: run the iPhone app and embed/install the Watch app.
- `SleepKitProbe Watch App`: run or preview the Watch app UI.

For real device testing, use `SleepKitProbe` with a paired iPhone + Apple Watch destination.

For Watch UI preview:

1. Open `WatchApp/WatchContentView.swift`.
2. Select the `SleepKitProbe Watch App` scheme.
3. Select an Apple Watch simulator destination.
4. Open Canvas and resume the preview.

## Install on iPhone + Apple Watch

1. Open `SleepKitProbe.xcodeproj`.
2. Select your development team for both targets:
   - `SleepKitProbe`
   - `SleepKitProbe Watch App`
3. Confirm capabilities:
   - iOS target: HealthKit.
   - Watch target: HealthKit.
4. Select the `SleepKitProbe` scheme.
5. Select your paired iPhone + Apple Watch destination.
6. Run.
7. Grant Health permissions when prompted.

If the Watch app fails to install, remove old copies from both iPhone and Watch, clean the build folder, then run again.

## Daytime Short Test

1. Open `Sleep Probe` on Apple Watch.
2. Tap `Start Session`.
3. Keep the wrist still for 5 minutes.
4. Move the wrist for 1 minute.
5. Tap `Stop Session`.
6. Open the iPhone app and go to the `Watch` tab.
7. Tap `Request Watch Sync` if needed.
8. Tap `Export Epoch CSV`.

Expected result:

- `watch_epoch_summaries.csv` has consecutive epochs.
- Still periods have lower `motion_score`.
- Moving periods have higher `motion_score`.
- `predicted_state`, `asleep_probability`, and `estimated_sleep_seconds` are populated.
- Heart-rate fields may be empty if watchOS does not provide passive heart-rate samples during the test epoch.

## Overnight Test

1. Charge the Watch enough for overnight use.
2. Set a normal system alarm as backup.
3. Open `Sleep Probe` on Watch before sleep.
4. Tap `Start Session`.
5. Sleep normally while wearing the Watch.
6. In the morning, tap `Stop Session`.
7. Open the iPhone app `Watch` tab.
8. Tap `Request Watch Sync`.
9. Export `watch_epoch_summaries.csv` and `watch_events.csv`.
10. Open Apple Health so official sleep data appears.
11. Use the existing HealthKit refresh/export flow to export `sleep_samples.csv`.

Primary Phase 2 question: did Watch record continuous overnight epochs with usable motion score, heart-rate availability, battery level, and estimated sleep state?

## Motion Score

Current definition:

```text
motion_score = standard deviation of acceleration magnitude inside one epoch
```

Rough interpretation:

- `0.000 - 0.015`: very still
- `0.015 - 0.035`: light movement, often sleep-compatible
- `0.035 - 0.120`: noticeable movement or turning
- `> 0.120`: strong movement, often awake/restless

These are starting thresholds, not validated clinical rules.

## More Docs

- `README_PHASE1.md`: original HealthKit real-time validation protocol.
- `README_PHASE2.md`: Watch-side sensor probe details.
- `Docs/phase1_healthkit_findings.md`: why HealthKit sleepAnalysis is post-hoc only.
- `Docs/phase2_watch_probe_protocol.md`: test protocol.
- `Docs/sensor_permissions.md`: permissions and capabilities.
