# Sensor Permissions

## iOS Target

The iOS app uses:

- HealthKit read permission for post-hoc sleepAnalysis evaluation.
- WatchConnectivity for receiving low-frequency Watch epoch summaries.

Health and sleep logs stay local unless the user explicitly exports files through the share sheet.

## Watch Target

The Watch app uses:

- Core Motion accelerometer data during a user-started session.
- HealthKit heart-rate access during a user-started session.
- Passive HealthKit heart-rate queries for samples watchOS already saved during each epoch.
- WatchConnectivity to send epoch summaries to iPhone.
- Local JSONL logging on Watch so data is not lost if iPhone connectivity is unavailable.

The default path does not start `HKWorkoutSession`. An experimental live HR path remains in code for future validation, but it can affect Activity rings and battery life.

Current default behavior:

- `motionSampleHz = 1`
- `epochSeconds = 60`
- `heartRateSamplingEnabled = true`
- `extendedRuntimeEnabled = false`

No private entitlements or private APIs are used.
