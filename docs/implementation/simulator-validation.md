# Simulator test execution — 2026-11-14

Source checkpoint: `b57f781` (clean before execution).

- Destination: already-booted iPhone 17 Pro, iOS 26.1 (23B86), arm64 simulator.
- Deployment target: iOS 16; this run does not establish execution on iOS 16.
- Result: **86 tests in 13 suites passed**, zero failures or skipped tests.
- `xcresulttool` confirms totalTestCount 86, passedTests 86, result Passed.
  Its per-device count is 93 because two parameterized tests expand into nine runs.
- Xcode reported `TEST SUCCEEDED`. An App Intents metadata warning said extraction
  was skipped because the package has no AppIntents dependency.

```sh
xcodebuild test -scheme SheepFence \
  -destination 'platform=iOS Simulator,id=2AE03597-C2A7-4B44-B8C1-08EAA9B11799' \
  -derivedDataPath .build/simulator-tests \
  -resultBundlePath .build/simulator-results-20261114.xcresult \
  -parallel-testing-enabled NO
```

Local result bundle: `.build/simulator-results-20261114.xcresult` (gitignored).
Build/test log: `/tmp/sheepfence-simulator-tests.log`.

This executed the package tests in the simulator, including the public client,
SQLite persistence, source policies, provider delegate tests and capacity workloads.
It does not validate a foreground host UI, live GPS routes, real-device permission
transitions, field accuracy, energy use or Release performance.
