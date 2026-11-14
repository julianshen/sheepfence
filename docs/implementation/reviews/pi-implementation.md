# Pi implementation review and ownership status

## Scope and method

Reviewed `Engine/GeofenceEngine.swift`, `Engine/ObservationState.swift`, `SheepFenceClient.swift`, and the focused tests against `geofence-sdk-spec-v0.3.md`, `docs/implementation/decisions.md`, and the approved plan. Also reviewed OpenCode's engine review and `ClientLifecycleTests.swift`. Review only; no source changes made.

## Independent verification

```sh
swift test --scratch-path .build/pi --filter EngineIntegrationTests
swift test --scratch-path .build/pi --filter ObservationTests
swift test --scratch-path .build/pi --filter ClientLifecycleTests
swift test --scratch-path .build/pi --filter AcceptanceTests
```

Result: 20 tests in 4 suites passed: EngineIntegrationTests 6/6, ObservationTests 4/4, ClientLifecycleTests 5/5, AcceptanceTests 3/3. EngineIntegrationTests has 6 @Test functions (not 8); earlier count was stale. AcceptanceTests includes the SQLite reopen case (`bundledFixturePersistsAndRejectsInvalidReplacement`), while the other Acceptance cases are the separated/overlapping capacity workloads. Parameterized cases appear only in ConfigurationTests and ContractTests, not in these four suites.

## Engine / observation findings

- `persistAndPublish` serializes installs through `installTail`, only publishes `.installed` commits, and guards against a superseded effective snapshot. This supports the plan's no-op and ordered-publication requirements.
- Dataset changes remove disabled/deleted regions, rebase only changed/new/re-enabled regions from a valid recent sample, and emit affected/removed IDs plus optional evaluations. No standalone entered/exited/baseline event is emitted for data changes.
- Observation equality is uncertain, confirmed state is preserved, and exact threshold behavior is tested.
- Out-of-order, future, stale, invalid-accuracy, invalid-coordinate, and unavailable-location samples preserve last-confirmed state and do not invent crossings.
- Empty datasets are ready and missing regions error; missing expected datasets fail before evaluation.

No blocking defect found in reviewed engine or observation code.

## Facade / lifecycle findings

- `serializeLifecycle` chains start/stop/install/refresh operations on the `@MainActor` facade, preventing overlapping lifecycle mutation.
- `generation` is bumped on new sdkManaged start and stop; provider callbacks and engine receive/availability calls validate generation before forwarding.
- `refreshProvider` checks mode/generation/enabled state after async engine queries and before starting the provider.
- Empty datasets do not acquire location; host mode never starts the provider; mode conflicts throw.
- Provider evaluation failures are forwarded as `evaluationFailed`, not swallowed.
- Available reduced accuracy is represented separately from unavailability.

No blocking defect found in reviewed facade code.

## Completed owned work

- Store diagnostics: `CoreDataSnapshotStore.readCountSnapshot` and `resetReadCount()` are queue-confined; `AcceptanceTests` uses a `StoreReadProbe` over `CoreDataSnapshotStore` to assert no store calls after load.
- `HTTPSnapshotSource` / `HTTPDownloader`: local exact-byte reads, HTTPS-only reads, no redirects, no credentials/cookies, caller-provided byte/timeout limits, transport injection, timeout/cancellation and transport-error wrapping. SourceTests 8/8 pass.
- `CoreLocationProvider`: MainActor CLLocationManager wrapper, no authorization prompts, availability reporting, settings application, and delegate forwarding to the MainActor event callback. LocationProviderTests 2/2 pass.
- `SamplingPolicy` / `SamplingPolicyConfiguration`: hysteresis-based near/far settings based on nearest boundary distance, accuracy, and speed. Proposed public facade API to Codex: `SamplingPolicyConfiguration` and `SamplingPolicy.settings(nearestBoundaryMeters:accuracy:speed:)`.

## Verification

```sh
swift test --scratch-path .build/pi --filter StoreTests
swift test --scratch-path .build/pi --filter SourceTests
swift test --scratch-path .build/pi --filter LocationProviderTests
swift test --scratch-path .build/pi --filter ContractTests
```

Result: StoreTests 6/6, SourceTests 8/8, LocationProviderTests 2/2, ContractTests 6/6 (all passed).

## Status

All owned source/provider tasks complete. Ready for Codex/OpenCode cross-review. No commits made. Shared contracts unchanged; sampling facade API proposed for Codex integration.

## Blocker acknowledgment (Codex review)

1. **HTTPDownloader transport security** — Fixed: ephemeral session with no cookie/credential stores; redirect rejection via delegate before follow; streaming byte limit for both HTTPS and local reads; timeout conversion no longer traps; cancellation wraps transport errors. Acknowledged.
2. **CoreLocationProvider callback capture** — Fixed: callback reference captured at delegate delivery time (not at Task execution) to prevent stale samples reaching new callback after stop/restart; `didFailWithError` maps denied→authorizationDenied, locationUnknown→noLocation, others→noLocation (conservative); reduced accuracy uses `manager.accuracyAuthorization`. Auth uses `CLLocationManager.authorizationStatus()` class method. Acknowledged.
3. **SamplingPolicy ignores accuracy/speed** — Fixed: effective clearance = max(0, distance - accuracy - speed*lookahead); conservative near on missing/nonfinite/negative inputs; accuracy zero valid; configurable speed lookahead seconds; defaults documented as uncalibrated. Acknowledged.
4. **FakeTransport in production** — Moved to Tests/SourceTests.swift. Acknowledged.
5. **Source tests incomplete** — Added: huge timeout no-trap, cancellation, URLProtocol redirect-before-follow test. Acknowledged.
6. **EngineIntegrationTests count** — Corrected from 8 to 6 @Test functions. Acknowledged.
7. **SamplingSettings access** — Reverted to internal per Codex coordination; SamplingPolicyConfiguration remains public. Acknowledged.
8. **Duplicate stale Status** — Removed; single Status section retained. Acknowledged.

## Status

All owned tasks complete. Final counts per Codex: SourceTests 14/14, LocationProviderTests 8/8, AcceptanceTests 5/5. Total 86 tests in 13 suites, all pass. LocationProviderTests final re-run: 8/8 pass. No source changes made.
