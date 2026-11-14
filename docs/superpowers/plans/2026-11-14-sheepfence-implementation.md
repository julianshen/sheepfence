# SheepFence v1 Implementation Plan

> **For agentic workers:** Use the executing-plans workflow task-by-task with the three explicitly assigned agents below. Steps use checkboxes for tracking. Do not create additional agents. This document authorizes planning only; implementation starts on the user's instruction.

**Goal:** Deliver the foreground iOS polygon-geofencing SDK defined by `geofence-sdk-spec-v0.3.md`, with transactional offline data, uncertainty-aware events, and reproducible acceptance evidence.

**Architecture:** Validate complete GeoJSON snapshots away from the main actor, commit datasets serially in Core Data, then publish immutable geometry snapshots. Separate pure geometry, observation state, and location acquisition. The host retains permission prompts and foreground lifecycle ownership.

**Tech Stack:** Swift 6, Swift Package Manager, Core Data, Core Location, Foundation/URLSession, CryptoKit, Swift Testing; no third-party geometry dependency is assumed.

---

## Starting point and boundaries

The package currently has models, configuration guards, client/store protocols, a sample fixture, and five passing test functions. There is no concrete engine, importer, geometry evaluator, store, downloader, or provider. Existing review evidence is in `docs/project-review/`. Local macOS tests and an iOS 16 simulator compile have passed; no functional SDK or real-device acceptance has passed.

Current checkout has no Git repository. Do not invent worktrees now. At implementation kickoff, establish the local repository and baseline commit, then create task branches/worktrees if available. Do not publish, tag, push, or merge to a shared branch without user authorization. If work stays in one directory, enforce the file ownership below and serialize integration changes. Preserve the original spec; record reconciliations in a separate decision document before editing it.

## Three-agent ownership and review rules

Use the **existing Herdr app workspace tabs** through `hc`: Codex is lead, OpenCode and pi are workers/reviewers. Rediscover addresses using `herdr-app ls`; current addresses are Codex `t7`, OpenCode `t9`, pi `t8`, not permanent identifiers. Do not start duplicate tabs or change agent models/settings. `herdr` is the legacy CLI; consult `hc --skill` and `~/.config/herdr-app/AGENTS.md` for current coordination.

| Agent | Primary implementation | Mandatory reviewer | Secondary review role |
|---|---|---|---|
| Codex | Public contracts, observation engine, concrete client, integration | pi; OpenCode additionally checks geometry/update semantics | Independently verifies import and persistence counterexamples |
| OpenCode | GeoJSON validation, geometry, bounding boxes, local distances | Codex | Reviews pi's store/source implementation and Codex's geometry use |
| pi | Core Data transactions, local/HTTPS source, Core Location provider | OpenCode; Codex verifies concurrency/failure cases | Reviews Codex's state machine and lifecycle contracts |

A reviewer must not approve their own implementation. Authors fix findings; reviewers rerun the exact counterexample after a fix. Reviews identify file/line, severity, trigger, expected/actual behavior, and validation evidence. A green suite alone does not close a finding. Record unresolved findings and exact reviewed commit/content identity in `docs/implementation/reviews/`.

Each task has two review passes: (1) spec/behavior correctness and (2) implementation quality, concurrency, and failure handling. A reviewer can perform both, but report them separately. Codex integrates only reviewed task results. No worker edits another worker's files or shared contracts without handing that change back to Codex.

## Gate 0: decisions before implementation

Create `docs/implementation/decisions.md`. Proposed decisions below are recommendations, not silently settled product requirements. Both peers review the contract diff before downstream work starts.

1. **Revision-bearing geometry query:** preserve spec section 6's Boolean `contains` convenience, and add `query(coordinate:in:) -> GeometryQueryResult` returning region identity, membership, and revision from one snapshot. Explicitly reconcile section 3's universal revision statement with the convenience exception. No separate revision lookup that can race a commit.
2. **Isolation:** keep Core Location lifecycle on MainActor. Use a dedicated engine actor for dataset publication and observation state; make client queries asynchronous across that boundary. Pure geometry functions operate synchronously over immutable Sendable snapshots. Replace the scaffold-wide synchronous MainActor constraint before freezing the API. Measure, rather than assume, query latency.
3. **Location source:** an explicit session mode (`hostProvided` / `sdkManaged`) prevents simultaneous sources. Host observations are submitted only in hostProvided mode; mode changes require stopping/resetting the session. Host permission/service changes have an explicit availability update path and clear baseline semantics.
4. **Freshness:** maximumLocationAge remains a required positive setting. Inject a clock, specify timestamp ordering, future timestamps, and out-of-order samples in decisions/tests. Proposed policy: ignore older samples for state transitions; classify future timestamps beyond a documented clock-skew allowance as unavailable. Choose the allowance before implementing this policy; do not invent a production age/latency default.
5. **Scope:** queries operate over installed datasets; an explicit requested missing dataset/region errors. An installed empty dataset is ready and yields no region results. Define behavior when none are installed and how applications declare expected datasets so a missing one is not silently treated as outside.
6. **Geometry limits:** preserve GeoJSON straight coordinate-segment containment. Establish the supported neighborhood extent and high-latitude handling for meter distances, and numeric boundary tolerances with test evidence. Do not silently reject globally valid data using arbitrary size/polar limits; record any supported-domain restriction as a spec decision.
7. **Version compatibility:** iOS 16 and Swift 6 remain provisional. Confirm minimum iOS before release. Benchmark iPhone, latency target, field accuracy/power thresholds remain release acceptance inputs; deterministic work can proceed without a timing threshold.
8. **Event contract:** define stream subscription/buffering/cancellation behavior; no silent loss of entered/exited events. Define dataset-change payloads (including changed/deleted IDs and baseline results) and revisions. Metadata-only updates must not reset existing baselines; changed geometry/newly enabled regions do.
9. **Download policy:** propose rejecting all redirects initially, no ambient cookies/credentials, and requiring finite positive download-byte and timeout limits in configuration. Exact limits are caller-supplied until a product default is chosen. Enforce byte limits during receipt, including chunked responses without Content-Length; cancellation never hands partial data to the importer. Review any later redirect support as a deliberate feature.
10. **Deterministic order:** priority descending, feature ID ascending; use dataset ID as a deterministic final tie-breaker for equal feature IDs across datasets, documented as an addition to the spec.

### Task 0 — freeze contracts (Codex; review OpenCode + pi)

**Files:** Modify `Sources/SheepFence/{Models.swift,Configuration.swift,GeofenceClient.swift}` and `Sources/SheepFence/Storage/SnapshotStore.swift`; create `Sources/SheepFence/Geometry/GeometryTypes.swift`, `Sources/SheepFence/Import/ValidatedSnapshot.swift`, `docs/implementation/decisions.md`, `Tests/SheepFenceTests/ContractTests.swift`.

- [ ] Draft result, snapshot, observation-input, event, source-mode, clock, and storage contracts for both workers to consume. Codex owns the initial SnapshotSource and LocationProvider protocols, the host-facing availability update method, and `Tests/SheepFenceTests/Support/PreparedSnapshotBuilder.swift`; pi implements those frozen protocols thereafter.
- [ ] Add contract tests for revision identity, empty-versus-missing datasets, and supported client calls; run `swift test --filter ContractTests` and record the intended failing condition.
- [ ] Implement value types/contracts only, then rerun the focused tests. Keep raw decoded data distinct from validated geometry.
- [ ] Have both peers review the decisions and public API; resolve blockers before handing out parallel tasks. Exit requires tests compiling against the chosen revision-bearing query and Boolean convenience exception, source-mode exclusivity, host availability updates, and empty/missing dataset behavior. Pure GeometryQueryResult intentionally has binary membership; CLLocation-based RegionEvaluation separately carries uncertainty/unavailability.
- [ ] Commit the reviewed contract baseline locally. Attach the commit ID to both task prompts.

Contract sketch (final names are set in Task 0):

```swift
public struct GeometryQueryResult: Sendable {
    public let regionID: RegionID
    public let revision: Int
    public let membership: Membership
}
// A prepared dataset contains metadata, exact input bytes, SHA-256,
// validated region attributes, geometry, and derived bounds.
// Store commit returns the effective committed dataset, not only an outcome.
// This prevents a skipped older candidate from becoming the memory snapshot.
```

## File ownership map

| Owner | Files/directories to create or modify |
|---|---|
| Codex | Existing public Swift files; `Engine/{GeofenceEngine,ObservationState,EventHub,Clock}.swift`; `SheepFenceClient.swift`; `Tests/SheepFenceTests/{ContractTests,ObservationTests,EngineIntegrationTests,AcceptanceTests}.swift`; shared fixtures and manifest changes |
| OpenCode | `Import/{GeoJSONDecoder,GeometryValidator,ImportDiagnostic}.swift`; `Geometry/{Bounds,Containment,BoundaryDistance,SegmentPredicates}.swift`; `Tests/SheepFenceTests/{ImportTests,GeometryTests}.swift`; `Fixtures/Geometry/` |
| pi | `Storage/{CoreDataModel,CoreDataSnapshotStore}.swift`; `Sources/{SnapshotSource,HTTPDownloader}.swift` under `Sources/SheepFence/`; `Location/{LocationProvider,CoreLocationProvider,SamplingPolicy}.swift`; `Tests/SheepFenceTests/{StoreTests,SourceTests,LocationProviderTests}.swift`; `Fixtures/Storage/` |

Task 0 creates shared GeometryTypes/ValidatedSnapshot definitions; subsequent changes go through Codex. Pi owns the concrete store but cannot independently rewrite its protocol. New test resources in distinct fixture subdirectories are already covered by the manifest's resource processing; only Codex edits Package.swift.

## Dependency schedule

| Wave | Codex | OpenCode | pi | Exit gate |
|---|---|---|---|---|
| 0 | Task 0 contracts/decisions | Contract review | Contract review | Agreed types, semantics, local baseline |
| 1 | Task 4 pure observation logic | Tasks 1–2 import/geometry | Task 3 store using prepared test snapshots | Unit counterexamples pass; cross-reviews complete |
| 2 | Task 5 install/query integration | Review store; assist geometry integration | Task 6 snapshot sources | Failed import/save preserves prior query result |
| 3 | Task 8 capacity fixture/oracle harness | Review engine/source semantics | Task 7 location provider | Both source modes and lifecycle validated |
| 4 | Task 9 final integration | Adversarial end-to-end review | Lifecycle/durability review | Functional acceptance and reproducible report |

Task 4 can use hand-authored region observations before geometry exists. Task 3 uses validated test snapshots agreed in Task 0, not a duplicate importer. Task 5 waits for Tasks 1–4; downloader wiring follows Task 6. Task 7 depends on the agreed source/availability contract and integrates after Task 5. Pause a worker's implementation when they are the required reviewer; concurrent edits are optional, independent review is mandatory.

## Implementation tasks

For each task below, repeat this small loop per listed behavior: write one focused failing test → run it and confirm the relevant failure → implement the smallest coherent behavior → rerun focused tests → request the assigned cross-review → fix/recheck findings → commit the reviewed unit. Do not mark a task complete on compilation alone. Split the task into small commits as needed.

### Task 1 — strict snapshot decoding and topology (OpenCode; review Codex)

**Files:** `Import/GeoJSONDecoder.swift`, `Import/GeometryValidator.swift`, `Import/ImportDiagnostic.swift`, `Tests/SheepFenceTests/ImportTests.swift`, `Fixtures/Geometry/*.geojson` (paths under the owner roots above).

- [ ] Decode schema/collection/feature types and required fields; reject wrong JSON types, unsupported schema, empty IDs, duplicate IDs, nonpositive/nonintegral revisions and wrong optional-property types. Retain exact bytes separately from parsed content.
- [ ] Validate UTC RFC3339 `generatedAt` ending in Z, including allowed fractional seconds. Defaults: name=ID, enabled=true, priority=0. Empty feature arrays are valid.
- [ ] Validate finite 2D coordinate pairs/ranges, closed rings, three distinct noncollinear vertices, self-intersections, holes outside shells, and overlapping holes; define touching-ring cases explicitly rather than relying on winding alone.
- [ ] Support Polygon and MultiPolygon. Ring position alone defines role: first shell, subsequent holes. Accept either winding on read, and normalize to counterclockwise shell/clockwise holes if canonicalizing; do not repair invalid topology by changing roles. Test reversed windings with valid topology and malformed holes with exact error paths. Reject unsplit antimeridian crossings under the agreed rule and test the positive cut representation.
- [ ] Emit feature ID and stable JSON field path for failures; invalid snapshots yield no partially accepted regions.
- [ ] Run `swift test --filter ImportTests`. Expected: valid fixture accepted with both IDs; every invalid fixture fails at its asserted path. Codex independently constructs at least a bow-tie, a nested/overlapping-hole case and malformed revision.

### Task 2 — pure geometry and meter distance (OpenCode; review Codex)

**Files:** Geometry files listed above; `Tests/SheepFenceTests/GeometryTests.swift` and geometry fixtures.

- [ ] Implement segment predicates and boundary detection before ray casting; both outer and hole boundaries count inside, hole interiors outside, any MultiPolygon component can hit.
- [ ] Implement bounds and containment separately from distance. A rectangle hit is never a final inside verdict.
- [ ] Compute nearest boundary distance across outer/hole/component edges using the agreed local meter mapping, consistent with coordinate-linear GeoJSON edges. Test endpoints, degenerate segments and near-horizontal/vertical edges.
- [ ] Candidate filtering uses enabled regions whose bounds expanded by accuracy radius + buffer (with conservative mapping/tolerance) can intersect the point, union prior inside/confirmed states needed for exit handling. A raw point-only bbox miss cannot exclude uncertainty contact. Preserve accurate observations for every enabled region; certain-outside fast paths need a proved bound, not skipped output.
- [ ] Test shared edges, holes, second MultiPolygon component, signed coordinates, split antimeridian data and supported high latitudes/extent. Independent analytic shapes supply expected distances; do not use the implementation as its oracle.
- [ ] Run `swift test --filter GeometryTests`. Codex independently tests hole edges and an outside-bbox point whose accuracy disk touches the region. Record numeric error bounds and assumptions.

### Task 3 — durable dataset store (pi; review OpenCode + Codex)

**Files:** `Storage/CoreDataModel.swift`, `Storage/CoreDataSnapshotStore.swift`, `Tests/SheepFenceTests/StoreTests.swift`, storage fixtures.

- [ ] Create a programmatic Core Data model (avoid a hidden Xcode-only generation dependency): dataset unique ID, revision, date, original bytes and SHA-256; region identity/attributes/geometry/bounds with dataset relationship.
- [ ] Implement startup loading of committed data and actor/queue confinement for all managed objects; only Sendable value snapshots leave the store.
- [ ] Serialize complete revision-check/save operations, not merely actor entry. Await/reentrancy cannot permit two commits to compare against the same stale revision.
- [ ] Test older-skip, exact-byte same-revision retry, different-byte same-revision conflict, empty replacement, and removed regions. Check digest and original-byte identity consistently.
- [ ] Commit all dataset/region replacements in one save. Inject save failure and verify rollback; use a temporary SQLite store for close/reopen checks (in-memory stores alone cannot establish durability).
- [ ] Control interleavings of revisions 4/5 and failed higher revisions. The final committed version is the highest successfully committed version, not the most recently started request.
- [ ] Run `swift test --filter StoreTests`. OpenCode reviews replacement/identity semantics; Codex independently reruns concurrent-commit and failed-save/reopen counterexamples.

### Task 4 — observation transitions and event rules (Codex; review pi)

**Files:** `Engine/ObservationState.swift`, `Engine/Clock.swift`, `Engine/EventHub.swift`, `Tests/SheepFenceTests/ObservationTests.swift`.

- [ ] Implement a pure transition function with injected time and explicit session generation. No baseline exists before first confirmed observation.
- [ ] Confirm only when `d > horizontalAccuracy + buffer`; equality is uncertain. Uncertainty preserves last-confirmed membership, timestamp and revision without crossing events.
- [ ] Emit one baseline then only actual confirmed changes; repeat observations produce no duplicate entered/exited events. Each overlapping region progresses independently.
- [ ] Handle no location, invalid accuracy, invalid coordinate, stale/future/out-of-order samples and permission/service loss under Gate 0 policy. Reset baselines on interrupted sessions; discard callbacks from a prior generation after stop/restart.
- [ ] For dataset updates, remove deleted/disabled state; rebase changed/new/re-enabled geometry using only a still-valid recent sample. Metadata-only changes preserve state. Publish the adopted revision, affected/deleted IDs and reevaluation results in datasetChanged. No standalone entered/exited or movement-baseline event is emitted merely because data changed. If no valid sample exists, include explicit unconfirmed state, never fabricate a baseline. A later first confirmed observation can establish a baseline normally. Test new, expanded, re-enabled, disabled, deleted and metadata-only regions, expired sample, startup without sample and update during stopped monitoring.
- [ ] Implement the agreed stream lifecycle and cancellation behavior. Test ordering and subscriber cancellation, including the chosen slow-consumer policy.
- [ ] Run `swift test --filter ObservationTests`. Pi independently tests uncertainty on first observation, exact threshold equality, stop/start stale callback and data-update baseline reset.

### Task 5 — atomic install and query engine (Codex; review pi + OpenCode)

**Files:** `Engine/GeofenceEngine.swift`, `SheepFenceClient.swift`, `Tests/SheepFenceTests/EngineIntegrationTests.swift`.

- [ ] Restore committed datasets on startup; install bundled files through the same revision rules. Queries distinguish ready-empty from missing data.
- [ ] Parse/validate/build the candidate snapshot off the UI actor; await serialized store commit; publish only the effective committed snapshot. No failing or skipped candidate replaces live geometry.
- [ ] Propagate unchanged and olderVersionSkipped without publishing datasetChanged, rebasing state, resetting last-confirmed time, or changing active geometry. Conflicts and other failed installs likewise leave geometry/state/events unchanged except the explicit install error. Add engine-level tests: establish a confirmed inside state, retry identical bytes, submit an older revision, then submit a conflicting same revision; assert no data-change/baseline/crossing event and the same active snapshot and confirmation.
- [ ] Keep memory publication ordered with durable commits, even if callbacks resume in reverse order. Define the query linearization point and test old-or-new whole snapshots, never partial mixtures.
- [ ] Evaluate all enabled regions from a captured immutable snapshot, return deterministic ordering, and carry revision/time/last-confirmed data through results and events.
- [ ] Route dataset changes through the transition logic; test multiple datasets with duplicate feature IDs, deleted regions, expanded polygons and expired recent samples.
- [ ] Run `swift test --filter EngineIntegrationTests`. Pi injects a save failure and reordered completions; OpenCode verifies bbox exit detection and geometry-update semantics. Assert no query-time Core Data fetches with store instrumentation.

### Task 6 — local and HTTPS snapshot sources (pi; review OpenCode)

**Files:** `Sources/SnapshotSource.swift`, `Sources/HTTPDownloader.swift`, `Tests/SheepFenceTests/SourceTests.swift`.

- [ ] Accept bundle/local file URLs and HTTPS; reject unsupported schemes and HTTPS-to-HTTP redirects. Keep request content limited to obtaining datasets, never sending location/history.
- [ ] Inject transport and file reading for deterministic tests. Implement Gate 0 redirect/credential policy and explicit caller-configured byte/time limits. Test same-host and cross-host HTTPS redirects, downgrade, loops, oversize Content-Length and chunked bodies, timeout and cancellation. Limits have explicit errors; only complete original response bytes and source metadata reach the importer atomically.
- [ ] Pass exact response bytes to the production installer. Test malformed response, interrupted transfer, non-2xx, unsupported redirect and cancellation preserving old data.
- [ ] Run `swift test --filter SourceTests`; use a fake transport/URLProtocol, not live Internet. OpenCode reviews failure atomicity and exact-byte identity.

### Task 7 — foreground provider and sampling (pi; review Codex)

**Files:** `Location/LocationProvider.swift`, `Location/CoreLocationProvider.swift`, `Location/SamplingPolicy.swift`, `Tests/SheepFenceTests/LocationProviderTests.swift`; Codex alone wires the concrete client.

- [ ] Wrap CLLocationManager behind the Task 0 MainActor provider, with fake provider tests. SDK does not trigger authorization prompts. Implement the Codex-owned host availability update API in hostProvided mode and provider delegate inputs in sdkManaged mode; both produce locationAvailabilityChanged and baseline resets on loss. Cover not-determined, denied, restricted and disabled services. Report precise/reduced accuracy changes without treating reduced accuracy alone as unavailable; use actual horizontalAccuracy for uncertainty.
- [ ] Implement idempotent start/stop, explicit source selection and lifecycle reset. No SDK location requests in hostProvided mode; no dual feed in sdkManaged mode. Ignore stopped-session callbacks.
- [ ] Stop acquisition when no enabled regions remain; restart appropriately when data enables regions and a foreground session is active. Availability loss resets confirmation state.
- [ ] Implement a configurable sampling policy based on nearest relevant boundary, accuracy radius and valid speed; unknown speed still works. Test near/far transitions and hysteresis to avoid rapid setting oscillation. Field-tuned values are not claimed before measurement.
- [ ] Run `swift test --filter LocationProviderTests`. Codex independently checks source exclusivity, revoked permission, background/foreground restart and region-enable restart. Physical-device observation follows Task 9.

### Task 8 — functional and capacity oracles (Codex; review OpenCode + pi)

**Files:** `Tests/SheepFenceTests/AcceptanceTests.swift`, `Tests/SheepFenceTests/Support/CapacityFixtureFactory.swift`, `Fixtures/Acceptance/`, `docs/implementation/acceptance.md`.

- [ ] Map every spec section 8 row to a named test using the real importer/store/engine, not a direct geometry bypass. Include offline bundled v3 garden+campus queries, first-inside baseline only, hole/boundary/MultiPolygon queries, rejected v4 retaining v3, concurrent v4/v5, deletion/expansion/restart, and unavailable-location reasons in both source modes where applicable.
- [ ] Generate two deterministic sets of 100 simple 100-edge polygons, closed with 101 coordinates. One set has disjoint bounds; the other shares an interior. List independently known expected IDs/points before querying.
- [ ] For separated data: query each interior and one all-outside point; assert exact IDs and zero Core Data reads after load. Choose accuracy/buffer safely below independently known boundary distances for the spec capacity oracle. Add a separate uncertainty case outside a raw bbox whose accuracy disk/buffer reaches an edge: assert boundaryUncertain, preserved confirmation and no crossings; retain the zero-fetch assertion.
- [ ] For overlapping data: outside baseline → common interior → same interior → outside; assert 100 unique matches and exactly one enter/exit per region with correct revisions.
- [ ] Run `swift test --filter AcceptanceTests`. OpenCode verifies geometric oracles; pi verifies that tests actually exercise Core Data and event counts.

### Task 9 — integration, documentation and release evidence (Codex; review both peers)

**Files:** `README.md`, `Examples/ForegroundHost/README.md`, `docs/implementation/{acceptance,performance}.md`; add an executable iOS sample/benchmark host under `Examples/ForegroundHost/` when the baseline target is confirmed.

- [ ] Run `swift test` and iOS simulator compilation; resolve all actionable cross-review findings. Report platform/toolchain and actual test counts.
- [ ] Build a minimal host demonstrating permission requests, plist purpose text, host-provided and SDK-managed modes, bundle install, event consumption, and stop on leaving foreground. Do not claim compilation of the library proves lifecycle behavior.
- [ ] On a real iPhone, verify location/service/permission transitions and foreground restart with expected-versus-actual observations.
- [ ] In Release on the selected device, measure both capacity distributions from valid-location receipt through completed evaluation, excluding GPS/download/startup. Record sample count, P50/P95, device, OS, configuration, dataset revision, warmup and measurement method. Record zero-fetch instrumentation results separately from uninstrumented timing; verify zero-fetch behavior in the Release host as well as the deterministic test harness. No performance pass/fail until product threshold is supplied.
- [ ] Run a representative-site field protocol: stationary boundary jitter and near/far walking routes with independently recorded crossing times, varied location accuracy and valid/unknown speed. Compare adaptive sampling with a fixed-policy baseline under matched device/OS/session conditions. Record false/missed/late crossing observations, uncertainty frequency, enter/exit delay distributions, location update frequency and measured energy impact using platform profiling. Obtain host/user permission before recording device location traces; keep traces local and excluded from version control. Document duration, repetitions, routes and measurement limits. Agree field accuracy, delay and power thresholds with the product owner before declaring this gate passed; without site/device access, explicitly mark it pending. Pi runs provider/sampling measurements, OpenCode checks boundary-distance/oracle assumptions, Codex consolidates evidence.
- [ ] Have both peers review the final integrated revision and recheck their assigned counterexamples; record remaining gaps. Keep real-device/performance gates pending if hardware or product decisions are unavailable.
- [ ] Update README status only for implemented and verified features. Prepare release notes/version proposal separately; publishing/tagging requires user authorization.

## Review packet and completion criteria

Every handoff includes task IDs, allowed files, contract baseline, implementation commit/content identity, focused test commands/results, manual evidence, limitations and review questions. Reviewers may write their own report and temporary isolated repros, but source fixes return to the author. Never run two agents' builds against the same scratch directory concurrently; use `.build/codex`, `.build/opencode`, `.build/pi` or separate worktrees.

Suggested local verification (substitute task filter and private scratch path):

```sh
swift test --scratch-path .build/codex --filter ObservationTests
swift test --scratch-path .build/codex
swift build --scratch-path .build/codex-ios --triple arm64-apple-ios16.0-simulator --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"
```

Expected: all selected tests pass; simulator library builds. In a restricted shell, use workspace-local CLANG_MODULE_CACHE_PATH/SWIFTPM_MODULECACHE_OVERRIDE and SwiftPM `--disable-sandbox` only to avoid nested-sandbox failure. Do not interpret infrastructure errors as code failures or unexecuted checks as passes.

Completion is tiered: **unit subsystem ready**, **integrated functional acceptance ready**, then **device/release acceptance ready**. Final SDK completion requires the spec acceptance cases, storage durability, concurrency/failure repros, device lifecycle evidence and agreed performance gate; a compiling scaffold or green unit suite alone is insufficient.

## Plan review status

**Revision 3 approved by both reviewers on 2026-11-14.** See [OpenCode final review](../../project-review/opencode-plan-review.md) and [pi final review](../../project-review/pi-plan-review.md).

Revision 2 incorporated explicit candidate, orientation, host-availability, download and acceptance contracts. Dataset-driven reevaluations remain within datasetChanged per spec section 3; pure coordinate results remain binary because uncertainty belongs to CLLocation evaluation. Revision 3 added pi's no-op install state/event invariants and representative field accuracy/power protocol. Both reviewers verified the final revision and reported no remaining plan blockers.

Approval concerns the plan's completeness, not execution or acceptance. Gate 0 decisions remain explicit implementation prerequisites. No implementation tasks have started. Execution will use the three existing agent tabs and cross-review ownership above.
