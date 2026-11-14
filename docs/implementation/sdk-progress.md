# SDK completion evidence — 2026-11-14

SDK implementation was completed and reviewed on `implementation/v1`, based on
commit `eb8ccd3`, and approved for integration into `main`. Release tags, version
selection, license selection and field accuracy/energy acceptance are not implied.

## Implemented surface

- Simplified persistent `open`, immutable configuration, fixed/adaptive sampling.
- Local/HTTPS/Data snapshot import with limits and structured redacted errors.
- Dataset/region catalog and atomic dataset removal.
- Pure `evaluate` returning `EvaluationBatch`; active-host-only `submit`.
- Coordinate membership and explicit supported/unsupported region distance.
- Atomic current state, GPS-unavailable/history semantics and recovery baselines.
- Bounded throwing subscriptions with initial snapshots and explicit overflow.
- Process-local canonical store exclusivity and safe pre/post-commit cancellation.
- Public payload initializers, CLLocation conveniences, migration guide, DocC and host.

## Three-agent implementation and review

| Work | Author | Independent evidence |
|---|---|---|
| Contracts | Codex | OpenCode + pi approved; 8 contract checks |
| Distance geometry | OpenCode | pi approved, 14 focused tests |
| Store/lease | pi | OpenCode approved, 20 initial focused tests; lease drift regression added during integration |
| Sources/provider/sampling | pi | OpenCode independently passed 33 focused tests |
| Engine/facade/events/integration | Codex | Both peers approved integrated implementation |
| Deterministic transaction cancellation tests | OpenCode | Codex reviewed queue handshake; both peers ran final suite |

Final full package results, same SDK source:

| Runner | Command | Result |
|---|---|---|
| Codex | `swift test --scratch-path .build/sdk-codex` | 139 tests / 25 suites passed |
| OpenCode | `swift test --scratch-path .build/sdk-opencode` | 139 tests / 25 suites passed |
| pi | `swift test --scratch-path .build/sdk-pi` | 139 tests / 25 suites passed |

Reviews: [OpenCode](reviews/sdk-opencode-review.md), [pi](reviews/sdk-pi-review.md).
A public-consumer regression caught a canonical lease key that changed after file
creation. Codex reproduced it independently; pi fixed final path normalization and
added tests for parent/file creation. Duplicate opens now fail consistently.

The combined production decoder + SQLite acceptance test deletes one region and
expands another while a controlled transport failure is suspended. Replacement
publishes only datasetChanged; failure preserves v4; reopen restores it. Networking
failure is injected at URLTransport; import/store/geometry/event paths are real.

## Platform/build evidence

- iPhone 17 Pro simulator, iOS 26.1: **139 tests / 25 suites passed** with official
  Xcode 27.2 tools. Result bundle `.build/sdk-simulator27-complete.xcresult`;
  log `/tmp/sheepfence-sdk-simulator-complete.log`.
- Xcode 26.1.1 simulator service connection failed after the newer system resources
  were installed; that run was stopped and replaced by the successful Xcode 27.2 run.
- DocC build succeeded: `.build/sdk-documentation/Build/Products/Debug-iphoneos/SheepFence.doccarchive`.
- Public symbol extraction succeeded: 273 symbols. [Inventory](sdk-public-symbols.txt)
  contains no exported engine, geometry, store, lease, provider or sampling implementation types.
- Signed Release iPhone host build succeeded. Compiler diagnostics clean; Apple's
  metadata processor reports its expected skipped AppIntents extraction notice.
- `git diff --check` passed.

## Physical iPhone evidence

Updated SDK host installed and launched on iPhone 18 Pro Max (`iPhone19,7`), iOS 27.0.1.
Fresh console output confirmed benchmark completion; [saved device report](sdk-iphone-benchmark-20261114.txt)
was retrieved from the app container. Release public pure-evaluation API, 100 areas ×
100 edges, 200 warmups and 2,000 measured queries per layout; all expected IDs verified.

| Layout | P50 ms | P95 ms | P99 ms |
|---|---:|---:|---:|
| Separated | 0.026791 | 0.028916 | 0.032875 |
| Overlapping | 0.085917 | 0.093042 | 0.267709 |

Includes public facade/actor dispatch; excludes import, verification and GPS. This is
one run, not a latency guarantee or an apples-to-apples comparison to the earlier
stateful evaluate implementation. The console attachment later timed out waiting for
normal app termination; benchmark completion had already been observed and saved.

The additional opt-in `--benchmark --sdk-smoke` host check passed after the phone
was unlocked. The [fresh device report](sdk-iphone-smoke-20261114.txt) contains the
explicit `SDK smoke passed` marker, verifying SDK-managed start/stop, host submit,
pure-query state isolation, distance, and explicit host noLocation/history. No
permission prompt or route test was performed. The accompanying repeated benchmark
also verified all region IDs: separated P50/P95/P99 0.026208/0.028708/0.031417 ms;
overlapping 0.087750/0.161791/0.460791 ms. Both runs are retained to show run variability.

Real permission-state transitions, route crossings, reduced-accuracy field behavior,
energy and accuracy/delay thresholds remain field acceptance work. No locations or
movement traces were uploaded or committed.
