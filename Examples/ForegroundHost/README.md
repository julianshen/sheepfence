# SheepFence Lab device host

Open `SheepFenceHost.xcodeproj`, select the connected iPhone and run the
`SheepFenceHost` scheme. The scheme runs **Release**. The project uses the local
SheepFence package and the same capacity fixture generator as the package tests.

Regenerate after editing `project.yml`:

```sh
xcodegen generate --spec Examples/ForegroundHost/project.yml
```

Select your development team and a unique bundle identifier in Xcode before
running on a physical device. Automatic signing is enabled; no team is committed.
The device must trust the Mac, have Developer Mode enabled (including restart and
post-restart confirmation), and be included in its provisioning profile.

## Controls

- **Run benchmark:** synthetic locations, no location permission needed. Runs both
  100-area × 100-edge layouts with 200 warmups and 2,000 timed queries each. Checks
  exact expected region IDs outside the timed interval. Reports P50/P95/P99 and
  allows sharing the result text. Keep the app in the foreground during the run.
- **Request location permission:** host-owned When In Use prompt.
- **Start SDK location / Stop location:** foreground provider/lifecycle check with
  bundled fictional campus polygons. Coordinates are not logged. Leaving the
  foreground stops tracking. Permission is never requested automatically.

Host benchmark timings use the public facade and include its actor dispatch. The
earlier package simulator benchmark times the internal engine. Do not compare
their numbers as identical measurement boundaries. Import and verification are
excluded from both timed intervals. No energy or real-route measurement is implied.

## Current setup evidence

2026-11-14: Release build, provisioning, installation and launch succeeded on
`iPhone19,7` / iOS 27.0.1. Official Xcode 27.2 device tools and developer image
27B52 resolved the earlier device-support blocker. The developer profile was
refreshed for the paired iPhone with user authorization.

Both 100-area benchmarks completed with exact expected region IDs verified.
See [physical-device results](../../docs/implementation/benchmark-iphone-20261114.md).

Launch with `--benchmark` to run automatically when foreground active and save
`Documents/benchmark-result.txt` inside the app container. Ordinary launches retain
the manual controls. This option does not request location permission.

Build product: `.build/device-host/Build/Products/Release-iphoneos/SheepFenceHost.app`.
