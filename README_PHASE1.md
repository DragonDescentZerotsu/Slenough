# SleepKitProbe Phase 1

SleepKitProbe is a local-only iOS research tool for checking whether Apple Watch / Apple Health `sleepAnalysis` samples appear in HealthKit during the night, and when this app actually receives those updates.

It is not an alarm product yet. It does not upload data, provide medical diagnosis, score sleep, or control the system Clock app.

## Prerequisites

- A Mac with Xcode.
- An iPhone device. The iOS simulator cannot validate real Apple Watch sleep data.
- A paired Apple Watch.
- Sleep tracking enabled in the iPhone Health app and Apple Watch sleep settings.
- Enough Apple Watch battery to wear it overnight.
- HealthKit Sleep Analysis read permission granted to SleepKitProbe.
- In Xcode, confirm the `SleepKitProbe` target has HealthKit capability enabled. This repo includes `SleepKitProbe.entitlements`, but your Apple developer team/signing settings may still need to be selected manually.

## One-Night Experiment

1. Open `SleepKitProbe.xcodeproj` in Xcode.
2. Select your developer team for the `SleepKitProbe` target if Xcode asks for signing.
3. Deploy the app to the iPhone.
4. Before bed, open SleepKitProbe.
5. Tap `Request HealthKit Permission`.
6. In the system Health permission sheet, allow Sleep Analysis read access.
7. Tap `Start Observer`.
8. Tap `Manual Refresh Last 24h` and confirm recent historical sleep samples appear if you already have sleep data.
9. Tap `Start Night Probe`.
10. Wear Apple Watch and go to sleep.
11. In the morning, open the app.
12. Tap `Manual Refresh Last 24h`.
13. Tap `Export CSV` and/or `Export JSONL`.
14. Save the exported files to Files or AirDrop them to the Mac.

## Exported Files

CSV export creates:

- `sleep_samples.csv`
- `observer_events.csv`

JSONL export creates:

- `sleepkit_probe_log.jsonl`

`sleep_samples.csv` contains `sample_start`, `sample_end`, `received_at`, `query_triggered_at`, `value_name`, `source_name`, and `sync_source`.

`observer_events.csv` contains each observer trigger, even when the anchored query found no new samples.

## How To Judge Results

### Case A: HealthKit may be timely enough

HealthKit-based MVP may be possible if the overnight logs show repeated samples where:

```text
observer_event.triggered_at is close to sleep_sample.sample_end
sleep_sample.received_at is close to sleep_sample.sample_end
```

Delays of minutes to tens of minutes may be workable for early experiments, depending on the product tolerance.

### Case B: HealthKit is not timely enough

HealthKit is probably only useful for review, not immediate wake-up timing, if most samples appear only after wake, unlock, or manual refresh. Example:

```text
sample_end = 03:10
received_at = 08:40
```

In that case, Phase 2 should likely move toward a watchOS companion app with its own awake/asleep detection.

## Important Notes

- `.immediate` background delivery is only a request. iOS still controls when observer callbacks are delivered.
- HealthKit read authorization status is privacy-protected; the app can request permission and attempt reads, but iOS does not expose a precise read-permission status value.
- The first observer startup primes the anchored-query anchor and intentionally skips older historical samples. Use `Manual Refresh Last 24h` or `Manual Refresh Last 7d` when you want recent history in the UI.
- Lock-screen and overnight delivery may be affected by system privacy, data protection, battery, and HealthKit scheduling.
- `inBed` is not counted as asleep-like time.
- Asleep-like values are `asleepUnspecified`, `asleepCore`, `asleepDeep`, and `asleepREM`.
- The displayed asleep-like duration is limited to the last 24 hours and unions overlapping asleep-like intervals to avoid double counting.
- This is a research validation tool, not medical software.

## Running Tests

Open the project in Xcode and run the `SleepKitProbe` scheme tests.

From Terminal, use a writable DerivedData path:

```bash
xcodebuild test -project SleepKitProbe.xcodeproj -scheme SleepKitProbe -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/SleepKitProbeDerivedData
```

The simulator cannot validate real Apple Watch sleep samples, but it can run pure Swift unit tests.
