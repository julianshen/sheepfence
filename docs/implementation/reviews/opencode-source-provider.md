# OpenCode read-only review: pi source/provider/store + Codex facade delta

**Scope (read-only):** `Sources/SheepFence/Sources/{SnapshotSource,HTTPDownloader}.swift`, `Sources/SheepFence/Location/{LocationProvider,CoreLocationProvider,SamplingPolicy}.swift`, `Sources/SheepFence/Storage/CoreDataSnapshotStore.swift` (diagnostics), associated tests (`SourceTests`, `LocationProviderTests`, `StoreTests`), and Codex facade/public delta (`SheepFenceClient.swift`, `PublicClientTests.swift`, `ClientLifecycleTests.swift`, `AcceptanceTests`, `GeofenceClient/Models/Engine` event surfaces). Reviewed against spec §3/§5-§7, `docs/implementation/decisions.md`, plan rev 3, and `docs/implementation/reviews/pi-implementation.md`. No source edits, no commits.

**Current checkout note:** some pi-owned sources currently **do not compile** in this workspace state (`swift build/test --scratch-path .build/opencode` fails in `HTTPDownloader` and `CoreLocationProvider`), while pi’s report states owned suites passed earlier in `.build/pi`. Findings below distinguish **concrete current blockers** from **previously-reported issues that appear addressed in current file contents** (to avoid evaluating old files as fixed).

## Focused test evidence (`.build/opencode`)

| Command | Result |
|---|---|
| `swift test --scratch-path .build/opencode --filter SourceTests` | **BLOCKED (compile error)** — `HTTPDownloader.swift:105,106,109` use `Data?` from `FileHandle.read(upToCount:)` as non-optional in local streaming read. Build failed before tests. |
| `swift test --scratch-path .build/opencode --filter LocationProviderTests` | **BLOCKED (compile error)** — `CoreLocationProvider.swift:82` sends `manager` into MainActor closure (`sending risks causing data races`), plus deprecated `authorizationStatus()` warning. Build failed before tests. |
| `swift test --scratch-path .build/opencode --filter StoreTests` | **BLOCKED by same compile errors** (package test target build depends on library). Pi reported StoreTests 6/6 in `.build/pi`; not reproducible in current `.build/opencode` state. |

## Concrete blockers

1. **High — `Sources/SheepFence/Sources/HTTPDownloader.swift:104-109` does not compile (local read streaming).** `FileHandle.read(upToCount:)` returns `Data?`; code treats it as `Data` (`chunk.isEmpty`, `chunk.count`, `append(chunk)`). This blocks `SourceTests`, full package build/tests, and any integration depending on local file snapshot installs. **Fix:** unwrap/guard `let chunk, !chunk.isEmpty` and append only non-nil chunks while preserving byte-limit enforcement.
2. **High — `Sources/SheepFence/Location/CoreLocationProvider.swift:80-84` does not compile under current concurrency rules.** `locationManager(_:didFailWithError:)` captures task-isolated `manager` in a `@MainActor` closure, reported as sending/data-race risk. **Fix:** read needed values (`accuracyAuthorization`/reduced-accuracy state) on delegate callback side before hopping, or capture only sendable values. (Separate from deprecated `authorizationStatus()` usage at `:40`, which is a warning but should be modernized for target APIs.)
3. **Medium — `HTTPSnapshotSource`/downloader timeout & redirect behavior not verifiable in focused tests (and may be incomplete vs spec/decisions).** Current `performHTTPS` races transport with `Task.sleep` timeout, but transport may ignore request timeout/cancellation and response size can still be fully buffered depending on `URLTransport` implementation; `EphemeralTransport` enforces byte cap while streaming bytes, but `FakeTransport` only checks final `data.count`. Tests cover happy path, non-2xx, URL-identity redirect, oversize, and transport error, but not **timeout**, **cancellation propagation**, **same-host/cross-host HTTPS redirect handling by delegate when transport follows redirects**, **chunked/Content-Length-less oversize during streaming**, or **redirect-to-HTTP downgrade**. Given decisions require rejection of redirects/cookies/credentials and explicit byte/time limits, Codex/pi should add/confirm deterministic tests for these cases before acceptance.
4. **Low — store read-count instrumentation likely over-counts vs “zero Core Data reads/fetches after load” intent.** `CoreDataSnapshotStore.perform` increments `readCount` for every queued operation, including commits/writes (`:81, :177-180`). `StoreTests`/`AcceptanceTests` currently compare deltas/calls in specific ways, but the counter name/semantics are easy to misread in future acceptance evidence. **Fix/suggestion:** track fetch/read operations separately (or name as “store operations”) and ensure acceptance asserts post-load query-time fetch/read count is zero per §8.1 wording.

## Previously-reported Codex blockers — status in current files

- **Credentials/cookies / redirect handling:** `HTTPDownloader` now uses `URLSessionConfiguration.ephemeral` with no cookie/credential stores and redirect rejection delegate (`:18-51`), and checks response URL identity (`:130-133`). `URLTransport` streams bytes with byte cap (`:35-44`). **Appears addressed in implementation direction**, but needs compile + deterministic redirect/timeout tests (see blocker #3).
- **Reduced accuracy property:** `CoreLocationProvider.reportAvailability()` and `didFailWithError` now use `manager.accuracyAuthorization == .reducedAccuracy` (`:47, :81`). **Appears addressed** (subject to compile fix).
- **`didFailWithError`:** implemented (`:80-85`). **Appears addressed**.
- **Sampling inputs/smoke:** `SamplingPolicy` now considers distance/accuracy validity and speed (`:52-72`) and `LocationProviderTests` includes hysteresis/near-far behavior (`:14-21`) plus provider settings smoke. **Partly addressed**, but coverage remains thin (no invalid-accuracy/unknown-distance/speed transition tests shown).

## Facade/public delta review (Codex-owned, read-only)

- **`SheepFenceClient.open(...)` (`SheepFenceClient.swift:25-48`):** restores committed snapshots on a detached task via `CoreDataSnapshotStore(url:)`, checks cancellation, constructs engine with production `HTTPSnapshotSource`, `GeoJSONDecoder`, and `Geometry` operations (including conservative `isCandidate`), then injects `CoreLocationProvider` and MainActor-owned sampling state/reset. This matches plan intent (restore before use, production source/geometry wiring, host-owned store URL/policy/lifecycle).
- **Sampling state/reset (`:38-47, :129-136`):** sampling policy is MainActor-contained and `resetSampling()` reapplies conservative initial settings before provider start. Correct direction for session/reset safety; depends on `SamplingPolicy` correctness/coverage.
- **Lifecycle serialization/generation (`:50-104, :106-138`):** `serializeLifecycle` chains async lifecycle work, start/stop bump generation and gate stale callbacks, `refreshProvider` rechecks mode/generation/enabled state after async engine calls and applies sampling only for current session. Aligns with prior facade review and decisions (`noLocation` on start, `evaluationFailed` forwarded from provider path via engine, idempotent start, stop clears callback/provider).
- **Public client integration:** `PublicClientTests` exercises open/install/query/persist/reopen and host-mode evaluation path using external package import and file-backed SQLite/download policy. `ClientLifecycleTests` and `AcceptanceTests` deltas (read) are consistent with `evaluationFailed`/`noLocation` and store instrumentation usage, but cannot be validated in `.build/opencode` until compile blockers are fixed.

## Coordination notes for pi / Codex

- **For pi (t8):** unblock compile first (`HTTPDownloader` optional chunk handling; `CoreLocationProvider` sendable/MainActor capture in `didFailWithError`, and modernize deprecated auth API). Then add deterministic tests for timeout/cancellation, redirect rejection (including delegate-followed redirects/downgrade scenarios as representable), and streaming/chunked byte-cap enforcement. Reconcile `SamplingPolicy` public/internal API and proposed facade integration (pi report proposes public settings API; current `SamplingSettings`/`SamplingPolicy` visibility and usage need a coherent contract).
- **For Codex (t7):** facade/public wiring looks directionally correct, but final integration should be revalidated after pi compile fixes with `SourceTests`, `LocationProviderTests`, `StoreTests`, `ClientLifecycleTests`, `PublicClientTests`, and acceptance zero-read assertions using clearly defined store-operation/read semantics.

**Overall:** not ready to approve current checkout as integrated (compile blockers in pi-owned files). Implementation direction appears substantially improved vs prior reported blockers, but requires compile fixes and stronger deterministic source/provider evidence.

## Recheck update (post-pi fixes, `.build/opencode`)

**Focused verification:**

| Command | Result |
|---|---|
| `swift test --scratch-path .build/opencode --filter SourceTests` | **PASS** — 11/11 tests, 1 suite |
| `swift test --scratch-path .build/opencode --filter LocationProviderTests` | **PASS** — 6/6 tests, 1 suite |
| `swift test --scratch-path .build/opencode --filter StoreTests` | **PASS** — 6/6 tests, 1 suite |
| `swift test --scratch-path .build/opencode --filter ClientLifecycleTests` | **PASS** — 6/6 tests, 1 suite |
| `swift test --scratch-path .build/opencode --filter PublicClientTests` | **PASS** — 1/1 test, 1 suite |

**Previous blockers status:**
- Prior compile blockers in `HTTPDownloader` and `CoreLocationProvider` are resolved in current checkout; focused suites now build/run.
- Source transport direction improved: ephemeral no-cookie/credential transport, redirect delegate rejection + final URL identity check, streaming HTTPS byte cap, local streaming read with cap, timeout/cancellation handling, transport error wrapping. Tests cover scheme rejection, local exact bytes/missing, HTTPS success/non-2xx/redirect/oversize, URLProtocol redirect-before-follow, huge timeout, cancellation non-crash path.
- Provider/sampling: `CoreLocationProvider` captures callback/reduced-accuracy/reason at delivery time and maps `didFailWithError` (`denied/locationUnknown/other`) appropriately in code; `SamplingPolicy` uses effective clearance with distance-accuracy-speed*lookahead, conservative near on missing/nonfinite/negative inputs, hysteresis. Focused sampling/provider tests pass.
- Facade/public delta: `SheepFenceClient.open` restore+production wiring, MainActor sampling state/reset-before-start, lifecycle serialization/generation invalidation, explicit `noLocation`/`evaluationFailed` flow remain directionally correct; `ClientLifecycleTests` and `PublicClientTests` pass in `.build/opencode`.
- Store diagnostics/read-probe usage remains compatible with reviewed acceptance intent in owned areas; `StoreTests` pass.

**Residual gaps / notes (not .build/opencode failures):**
- `CoreLocationProvider` still uses deprecated `CLLocationManager.authorizationStatus()` (`:40`, `:81`) with compiler warnings; should be modernized to instance/target-appropriate authorization APIs.
- `LocationProviderTests` is mostly sampling/policy-focused; it does not exercise real `CLLocationManager` delegate delivery, authorization transitions, `locationServicesEnabled` variations, or `didFailWithError` callback emission beyond code inspection.
- `SourceTests` cancellation case asserts “no crash” rather than required cancellation/download-failed semantics; redirect coverage proves delegate-before-follow for a synthetic redirect but not all downgrade/credential-leak scenarios end-to-end in a live transport stack.
- Full-package (79) and iOS 16 simulator build not independently rerun by me in this pass; Codex reported rerunning them.

**Final verdict (post test-only correction):** **Approved.** Focused reruns pass in `.build/opencode`: `SourceTests` 14/14, `LocationProviderTests` 8/8 (including deterministic delegate isolation and captured-at-delivery reduced-accuracy assertion in `providerErrorsHaveExplicitReasons`), `AcceptanceTests` 5/5. Source/provider/facade deltas and acceptance oracles are correct per reviewed evidence. Codex reports full 86/13 tests and iOS 16 simulator build pass with no warnings. Minor residual note: real-device/field/provider-OS behavior remains outside deterministic unit coverage, as already gated by plan. No source edits made by OpenCode.
