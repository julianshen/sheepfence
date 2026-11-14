# Physical iPhone benchmark — 2026-11-14

SheepFence Lab installed and launched successfully on iPhone 18 Pro Max
(`iPhone19,7`), iOS 27.0.1. Both synthetic correctness/performance workloads completed.
SDK baseline: `b57f781`, with the uncommitted example host and benchmark harness.
Release build: Xcode 26.1.1 (17B100); deployment used official Xcode 27.2 device
tools (CoreDevice 651.32) and Apple developer disk image 27B52.

Each layout contains 100 polygons with 100 edges each. There were 200 warmup and
2,000 measured queries per layout. Timings cover the public evaluate API including
actor dispatch, excluding import and expected-ID verification. All 100 results and
exact inside-region IDs were checked for every query, including warmups.
Synthetic samples use 1 m accuracy, a 86,400-second validity window and default
geofence buffer/sampling settings. No GPS access or location permission was needed.

| Layout | P50 ms | P95 ms | P99 ms |
| --- | ---: | ---: | ---: |
| Separated | 0.036833 | 0.040375 | 0.044000 |
| Overlapping | 0.093375 | 0.098125 | 0.104125 |

[Raw device report](benchmark-iphone-20261114.txt) was retrieved from the installed
app's Documents/benchmark-result.txt after launch with `--benchmark`.

This is one physical-device run, not the full package test suite or field acceptance.
GPS permissions, route crossings, lifecycle behavior and energy usage remain untested
on hardware. Product performance thresholds remain unspecified. Simulator timings
use the internal engine and therefore have a different measurement boundary.
