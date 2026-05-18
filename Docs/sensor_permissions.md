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
- A workout session to improve live heart-rate collection reliability in Phase 2.
- WatchConnectivity to send epoch summaries to iPhone.
- Local JSONL logging on Watch so data is not lost if iPhone connectivity is unavailable.

`HKWorkoutSession` can affect Activity rings. Phase 2 accepts this tradeoff for sensor validation; productization needs a more careful smart-alarm runtime design.

No private entitlements or private APIs are used.
