# flow

Big-picture health dashboard for iOS: HRV, active energy, and workout HR-zone
intensity from HealthKit. Read-only — flow writes nothing back to Health.

## Features

- **Overview tab** — latest HRV and resting HR with age, today's active energy,
  and 7/30/90-day trend charts for HRV and active energy.
- **Intensity tab** — recent workouts broken into the five classic HR
  zones (Recovery through Max, 50%–100%+ of HR max) with time-in-zone and
  average intensity per workout. This is the app's distinctive capability —
  `WorkoutIntensityService` pulls each workout's HR samples and buckets
  elapsed time by zone, capping gaps (sensor dropouts) so a paused workout
  doesn't dump minutes into one bucket.
- **Settings tab** — HR-max override for zone calculations, dashboard window
  picker (7D/30D/90D).
- **Offline-first tiles** — the last computed HRV/resting-HR/active-energy
  values are cached in a SwiftData `MetricSnapshot` on-device, so tiles render
  instantly on launch before HealthKit finishes its async refresh. HealthKit
  stays the source of truth; the snapshot is a cache, not a second copy of
  history.

## Requirements

- iOS 17+
- Xcode 15+
- Apple Developer team for code signing (HealthKit requires a real team)

## Project structure

```
flow/
├── flowApp.swift
├── Health/
│   ├── HealthKitService.swift        # read-only HK access: HRV/active energy/resting HR
│   ├── HRZone.swift                  # the 5 HR zones + pure time-bucketing (ZoneBucketer)
│   └── WorkoutIntensityService.swift # per-workout HR-zone breakdown, the app's core feature
├── Models/MetricSnapshot.swift       # SwiftData on-launch cache (CloudKit-safe: all optional)
├── ViewModels/DashboardViewModel.swift
└── Views/RootView.swift              # 3-tab root: Overview / Intensity / Settings
```

## Build

1. Open `flow.xcodeproj` in Xcode.
2. Select the **flow** scheme.
3. Choose a destination — HealthKit data is limited on the simulator, so a
   physical device with real Health history gives the most useful result.
4. ⌘R.

## License

Private project, no license declared.
