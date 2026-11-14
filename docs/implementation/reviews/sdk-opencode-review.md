# SDK OpenCode Independent Review — C1 engine (additive core)

**Reviewer:** opencode (read-only)  
**Scope reviewed:** current Codex C1 changes/additions only — `GeofenceEngine` (`evaluateOnce`/`submit`/`distance`/`eventStream`/`currentState`/bounded subscribers, availability & freshness-gap handling), `MonitoringSession`, `ObservationState`, `CommitGate`, and new `SDKEventTests`/`DistanceQueryTests`/`CommitGateTests`. Public API/protocol switch deferred to phase 3; legacy internal `events()`/`evaluate(location:)` retained for old-test compilation as noted by Codex.

## Evidence (coordinated freeze)
- Freeze requested/granted by t7 for SDKEventTests run (no in-flight Codex mutations; O1 remained frozen).
- `swift test --scratch-path .build/sdk-opencode --filter SDKEventTests` → **4 tests, 1 suite passed** (0 failures). Covers: pure `evaluateOnce` does not seed monitoring history/baseline state, per-subscriber bounded overflow fails only slow subscriber with `eventBufferOverflow`, GPS loss retains `lastConfirmed` while recovery emits baseline, `submit` requires active host mode and invalid buffer capacity rejected.
- Supplemental context observed in same tree (not re-run by me here): Codex reports 6/2 pass for `SDKEventTests`+`SDKContractTests`; `DistanceQueryTests` and `CommitGateTests` present and compile in this build state.

## Findings
- **No concrete defects found** in the reviewed additive C1 core.

## Notes (contract-aligned behavior observed)
- **Pure vs stateful split:** `evaluateOnce` validates sample/readiness only, builds per-region observations without mutating `ObservationState`/`recentSample`/`lastTimestamp` and returns `EvaluationBatch` with `lastConfirmed == nil`; emits nothing. `submit` requires active host (`session.requireActiveHostSource`) and routes through `evaluateAcceptedSource`.
- **Stateful ingestion / recovery:** accepted samples enforce ordering/freshness/validity, reset baselines on availability loss (`interrupt`, clear recent/timestamp) and on freshness gap since prior accepted sample (`> maximumLocationAge`), emit availability-acquired on first usable sample in active session when needed, then observe with baseline-after-interruption semantics and emit `.evaluated(batch)`; rejected/unavailable inputs produce unavailable evaluations and `.evaluated` without advancing accepted timestamp or fabricating crossings. `currentState` projects current availability/readiness/expired-or-missing observations without mutating history.
- **Event streams:** `eventStream(bufferCapacity:)` validates positive capacity, registers continuation before returning and yields initial `.stateSnapshot(currentState())`; bounded per-subscriber overflow terminates only that subscriber with `GeofenceError.eventBufferOverflow` (no silent drop/block). Legacy unbounded `events()` retained temporarily.
- **Commit/cancellation:** `CommitGate` prevents queued work after pre-begin cancel but cannot cancel once begun (durable outcome preserved); used in install path to gate commit start.
- **Distance query:** single snapshot/region lookup, explicit `Geometry.boundaryDistanceEstimate`, returns `RegionDistanceResult` (revision-attributed) with no state mutation/emission (consistent with `DistanceQueryTests`).

## Residual/non-blocking
- Legacy `evaluate(location:)`/`events()` and other phase-3 migration points remain intentionally until coordinated public switch; no blocking issue identified in additive core reviewed.

---

# SDK OpenCode Independent Review — P1 storage (frozen)

**Reviewer:** opencode (read-only)  
**Scope reviewed:** `Sources/SheepFence/Storage/{SnapshotStore.swift,CoreDataSnapshotStore.swift,StoreLeaseRegistry.swift}`, `Tests/SheepFenceTests/{StoreTests.swift,StoreLeaseTests.swift}` (pi frozen; pi reported 20/20 for `StoreTests|StoreLeaseTests`).

## Findings
- **No concrete defects found** in the reviewed storage implementation semantics.

## Notes (contract-aligned behavior observed)
- **Leases / canonicalization:** `StoreLease.acquire` requires absolute file URLs, canonicalizes by resolving longest existing real path prefix (parent symlinks) and appending/standardizing remainder so alias/nonexistent-store paths map consistently; process-local `NSLock` registry with per-lease token makes duplicate opens throw `storeAlreadyOpen`, release idempotent, stale-release safe, and `deinit` releases (lifetime/leak protection).
- **Transactional commit/rollback:** compare/replace/save serialized on one queue/context; `beforeSave`/save failures roll back context and preserve prior durable snapshot (SQLite reopen covered by tests). Revision rules preserve unchanged/older/conflict outcomes and effective snapshot; held older vs newer/failed-higher cases covered by gates/interceptors.
- **Removal:** `removeDataset` is transactional (durable before return), returns sorted `removedRegionIDs` via `regionIDOrder` (datasetID, then featureID), missing ID is idempotent no-op (`wasPresent=false`, no data change), failed removal rolls back/preserves old data, removal scoped to named dataset and later reinstall can recreate.
- **Errors/lifetime:** directory/create/load/decode/save/remove failures surfaced as `storageFailed`/relevant errors; init creates missing parent directories for file stores; lease re-acquire possible after release/dealloc.

## Observed build note (non-storage, cross-file)
- `swift test --scratch-path .build/sdk-opencode --filter SDKCancellationTests` failed to build in this tree due to `Tests/SheepFenceTests/StoreLeaseTests.swift:103` (`group.addTask` body throws from `try StoreLease.acquire`) before tests executed; pi has indicated a canonicalization/assertion fix in progress but I did not rerun tests (global freeze required). Reported for coordination; not a storage-logic defect.

**Coordination:** Requested global source freeze before running `SDKCancellationTests` or any focused suites while pi starts P2 source/sampling edits. O1 remains frozen. No shared source/test edits made.

---

# SDK OpenCode Independent Review — P2 source/sampling (frozen source, read-only)

**Reviewer:** opencode (read-only)  
**Scope reviewed:** `Sources/SheepFence/Sources/{HTTPDownloader.swift,SnapshotSource.swift}`, `Sources/SheepFence/Location/SamplingPolicy.swift` (pi implementing owned P2 tests only).

## Findings
- **No concrete defects found** in reviewed P2 source against contract freeze v1 / accepted pins.

## Notes (contract-aligned behavior observed)
- **Download policy / source contract:** `DownloadPolicy.standard` = 5,000,000 bytes / 30s with positive+finite validation. `SnapshotSource.read(from:)` retained; `HTTPSnapshotSource`/`HTTPDownloader` throw `GeofenceError.sourceFailed(...)` directly (no double-wrap). Non-HTTPS remote schemes -> `.unsupportedScheme` (no URL echoed); local missing/unreadable -> `.fileRead`; redirects rejected (delegate returns nil) and mapped to `.redirectRejected` without target URL; HTTP status mapped to `.httpStatus`; transport/read/response failures mapped to structured `.network` without raw NSError/URLs; byte cap enforced during local chunk reads and streaming HTTPS receipt (`.byteLimitExceeded(maximumBytes:)`); timeout via racing task -> `.timeout`; `CancellationError` preserved/checked.
- **Sampling:** `LocationSamplingConfiguration` public `Sendable`/`Equatable` with throwing init validating finite `distanceFilterMeters >= 0` and finite `desiredAccuracyMeters > 0` (sentinel negatives excluded), `.standard` 10m/10m, internal `settings()` mapping. `SamplingMode` public enum `.fixed(LocationSamplingConfiguration) | .adaptive(SamplingPolicyConfiguration)`. `SamplingPolicy`/`SamplingSettings` remain internal; adaptive config/policy behavior and conservative fallback semantics unchanged.

## Residual/non-blocking
- `GeofenceConfiguration.downloadPolicy/sampling` and facade selection/integration remain Codex-owned phase-3 work per contract; not a P2 defect.

## Independent stable-tree verification (pi P1+P2 frozen)
- Coordinated with t7/stable tree (no pi mutations in flight), ran in own scratch path:
  - `swift test --scratch-path .build/sdk-opencode --filter 'StoreTests|StoreLeaseTests'` → **20 tests, 2 suites passed**.
  - `swift test --scratch-path .build/sdk-opencode --filter 'SourceTests|SamplingConfigurationTests|LocationProviderTests'` → **33 tests, 3 suites passed**.
- Reconfirmed review targets: storage rollback/removal-vs-install ordering and lease races/canonicalization (P1); source error mapping/redaction, `DownloadPolicy.standard`, and sampling types (P2). No concrete defects found. O1 remains frozen.

---

# SDK OpenCode Integrated Review — facade/protocol/core (read-only, while pi fixes lease drift)

**Reviewer:** opencode (read-only, no test commands)  
**Scope reviewed:** integrated `SheepFenceClient` facade, `GeofenceClient` protocol/extensions, `GeofenceEngine` core (install/remove serialization + CommitGate, pure `evaluateOnce` vs `submit`/stateful receive, bounded `eventStream`/`currentState` snapshots, availability/freshness/monitoring behavior, `distance` query), relevant public models/config/wiring as used.  
**Known issue (out of scope to fix):** 135/136 pass; sole reported failure is public duplicate-open after store creation due to lease canonical key drift (pi assigned). Not re-evaluated here.

## Findings
- **No additional concrete defects identified** in reviewed lifetime, pure-vs-submit, snapshots/events, or cancellation semantics.

## Notes (observed behavior)
- **Lifetime / ownership:** `open` acquires process-local `StoreLease` before store init, retains it across detached load and passes `lease.url` into store/engine; engine holds `storeLease` so reservation lives with the client/engine lifetime and is released on deallocation (including failed/cancelled paths where lease goes out of scope). Provider callbacks capture `weak self` and gate on mode/generation/engine generation; `stopMonitoring`/refresh serialize lifecycle work, stop provider, clear handler, and emit stopped state even when caller is cancelled (best-effort cleanup). Client `deinit` schedules provider stop/handler clear on main actor.
- **Pure query vs stateful submit:** `evaluateOnce` is side-effect-free (readiness/sample validation only, no mutation/emission, `lastConfirmed == nil`, batch returned). `submit` requires active host source and routes through stateful ingestion (`evaluateAcceptedSource`) which applies ordering/freshness/validity/availability handling, baseline resets on gap/availability loss, emits baseline/transition events and `.evaluated` batches, and updates accepted sample/latest tracking; provider ingestion uses the same stateful path with generation guards. `distance`/`query`/catalog reads do not mutate monitoring state or emit events.
- **Snapshots / events:** bounded `eventStream` validates capacity, registers before return, and yields an initial atomic `.stateSnapshot(currentState())`; overflow terminates only the affected slow subscriber with `eventBufferOverflow` (no silent drop/block of others). `currentState` projects readiness/availability/expired-or-unavailable observations from committed snapshot view without fabricating crossings; install publishes `datasetChanged` (with affected/removed IDs and rebase evaluations when applicable) after durable commit/publication, removal publishes `datasetRemoved` only when present after durable commit+memory update.
- **Cancellation / commit safety:** install/remove decode/check-cancel before queueing, serialize via tail + `CommitGate`; cancellation before `begin()` prevents queued durable work, while cancellation after begin cannot abort/publish-as-rolled-back a begun commit (durable outcome still completed/published). `install(data:)` enforces configured byte cap and maps store failures through SDK error normalization.

## Residual/non-blocking
- Prior known issue resolved: lease canonical-key drift (duplicate-open-after-create) fixed by pi; re-verified in final full suite.

---

# SDK OpenCode Final Integrated Review — verdict

**Reviewer:** opencode (independent, read-only on shared sources)  
**Source state:** frozen post-pi lease fix + regression coverage, public protocol/facade/test/host migration complete.

## Lease counterexample/fix inspected
- `StoreLeaseRegistry.canonicalStoreURL`: resolves longest existing `realpath` prefix (canonicalizes parent symlinks / `/var`↔`/private/var` reality), then lexically normalizes only the nonexistent suffix (handles `.`,`..`) **without** applying filesystem-sensitive `standardizingPath` to the resolved prefix. This prevents registry-key drift when `CoreDataSnapshotStore.init(url:)` creates missing parent dirs and the store file later exists.
- `SheepFenceClient.open` acquires lease first, uses `lease.url` for detached store init/load, retains lease in engine — matching exclusive-lifetime contract. `StoreLeaseTests` now include `canonicalKeyIsStableAcrossParentAndFileCreation` alongside alias/redundant-path and release/dealloc/token-safety cases; addresses prior duplicate-open-after-create counterexample.

## Full integration checks (independent)
- Prior final run: `swift test --scratch-path .build/sdk-opencode` → **138 tests, 24 suites passed, 0 failures**.
- Final run (incl. `SDKReplacementTests`): `swift test --scratch-path .build/sdk-opencode` → **139 tests, 25 suites passed, 0 failures**.

## Final acceptance addition reviewed (read-only)
- `Tests/SheepFenceTests/SDKReplacementTests.swift` (SDK source unchanged): real decoder + SQLite store, host monitoring submit baseline, controlled concurrent HTTPS failure via suspended transport, same-commit deletion+expansion replacement (rev 4). Verified `datasetChanged` (removed region + affected evaluation) without synthesized crossings/enter-exit, failed concurrent download surfaces `sourceFailed(.network)`, queries reflect rev 4/removal, stopped availability follows (no crossing), and restored durable snapshot is rev 4/garden only. No defects found.

## Verdict
**Approved (no blocking findings).** Integrated public API/facade, pure `evaluateOnce` vs stateful `submit`, bounded event streams with initial snapshots, catalog/removal/state/distance/replacement, source/sampling/lease/store behavior, and cancellation/commit semantics are consistent with frozen contract and green in final full-suite verification (139/25). Remaining release/field gates (physical host checks, energy/accuracy thresholds, license/version decisions) are out of this contract/integration review scope per plans.
