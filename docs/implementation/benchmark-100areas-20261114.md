# 100-area simulator benchmark — 2026-11-14

Executed on the iPhone 17 Pro **simulator**, iOS 26.1, arm64, using Xcode 26.1.1
(17B100). Source checkpoint `b57f781` plus `CapacityBenchmarkTests.swift`.
Release optimization (`-O`, whole-module optimization) enabled; testability enabled
for internal APIs; code coverage and parallel testing disabled.

| Layout | P50 ms | P95 ms | P99 ms | Mean ms | Maximum ms |
|---|---:|---:|---:|---:|---:|
| Separated | 0.043417 | 0.046875 | 0.052458 | 0.043932 | 0.104583 |
| Overlapping | 0.114709 | 0.118625 | 0.125750 | 0.114460 | 0.164625 |

Each layout contains **100 enabled areas × 100 edges = 10,000 edges**. Each run
uses 200 warmup queries followed by 2,000 measured queries. Percentiles use the
nearest-rank definition. One run per layout; these numbers do not estimate
run-to-run variability.

Data passes through the production GeoJSON decoder, commits to SQLite Core Data,
then restores into the engine's immutable snapshots before timing. ContinuousClock
measures the awaited `engine.evaluate(location:)`, including actor dispatch and all
100 region evaluations. Parsing, persistence/loading, sample construction and
correctness assertions are outside the measured interval. No event subscriber or
Core Location acquisition is active.

Separated queries rotate through all 100 independently known centers, expecting
exactly the corresponding region ID. Overlapping queries use the shared center,
expecting all 100 IDs. Every result was checked outside the timed interval; no
correctness failures occurred. Samples have increasing timestamps, 1 m horizontal
accuracy and zero buffer; the injected fixed clock keeps them valid. Dataset
revision is 1. These workloads measure confirmed interior evaluations, not edge
jitter or outside-to-inside transition latency.

Store operation counters were captured before/after each workload, outside the
timed intervals: **zero additional operations** for both layouts. Since evaluation
never enters the store, no store-counter increment executes within those queries.

## Reproduction and artifacts

```sh
xcodebuild test -scheme SheepFence -configuration Release \
  -destination 'platform=iOS Simulator,id=2AE03597-C2A7-4B44-B8C1-08EAA9B11799' \
  -derivedDataPath .build/simulator-benchmark \
  -resultBundlePath .build/benchmark-100areas-release.xcresult \
  -parallel-testing-enabled NO -enableCodeCoverage NO \
  -only-testing:SheepFenceTests/CapacityBenchmarkTests ENABLE_TESTABILITY=YES
```

Use a fresh result-bundle path when rerunning. The first Release attempt without
testability failed to expose the module to internal tests and produced no timings.
The command above succeeded: one benchmark test, both layouts, no failures.

- Raw metrics and dataset SHA-256: [JSON results](benchmark-100areas-20261114.json).
- Local Xcode result: `.build/benchmark-100areas-release.xcresult` (gitignored).
- Local console log: `/tmp/sheepfence-benchmark-release.log`.

The simulator runs on the Mac CPU; its device name is not evidence of iPhone
hardware speed. No product latency threshold was supplied, and no physical-device,
GPS, energy or field-accuracy acceptance is claimed.
