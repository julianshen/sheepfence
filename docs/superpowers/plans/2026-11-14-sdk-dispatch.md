# SheepFence SDK Dispatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task after user approval. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved SDK API using Codex, OpenCode and pi with disjoint ownership, independent reviews and reproducible acceptance evidence.

**Architecture:** Codex owns public contracts, engine and integration. OpenCode owns geometry distance. Pi owns storage/source/provider components. The existing shared Herdr workspace is retained; agents do not edit one another's files.

**Tech Stack:** Swift 6, SPM, Core Data, Core Location, Swift Testing, Xcode, existing Herdr tabs.

---

## Status and controlling documents

Approved by the user; implementation dispatched through the existing Herdr tabs. See `docs/implementation/sdk-progress.md` for current gates and evidence.
The [API proposal](2026-11-14-sdk-api.md) defines behavior; this document defines execution.
`geofence-sdk-spec-v0.3.md` remains the baseline, with proposed API amendments listed in the proposal.

Observed baseline: `implementation/v1`, last published commit `eb8ccd3`, GitHub `main`.
Recheck HEAD and working-tree changes at execution start. Preserve this plan and unrelated
changes. Previous results (86 package tests and physical benchmark) are baseline evidence,
not validation of the forthcoming implementation. Do not assume a new test count.

Use the existing Herdr workspace:

| Agent | Existing terminal | Responsibility |
|---|---|---|
| Codex | `t7` | Coordinator, contracts, engine, facade, integration, final verification |
| OpenCode | `t9` | Distance geometry, its component tests, independent reviews |
| pi | `t8` | Storage/source/provider components, their tests, independent reviews |

Live checked during planning: pi is idle; OpenCode displays its interactive input prompt
although `hc ls` labels its shell wrapper as zsh. Recheck with `hc ls --json` and
`hc read t8 --lines 20` / `hc read t9 --lines 20` before dispatch. Do not open extra
agent tabs or change agent models/providers. An unavailable agent is a named blocker,
not permission to claim its review or silently substitute another author.

## File ownership

| Owner | Exclusive write scope during parallel phase |
|---|---|
| Codex | `GeofenceClient.swift`, `Models.swift`, `Configuration.swift`, `SheepFenceClient.swift`, `Engine/*`, `Location/LocationProvider.swift` public value declarations; `SDKContractTests.swift`, `SDKEventTests.swift`, `EngineIntegrationTests.swift`, `ClientLifecycleTests.swift`, `PublicClientTests.swift`, `AcceptanceTests.swift`, `DistanceQueryTests.swift`; example host, README, DocC, migration and API docs |
| OpenCode | `Geometry/BoundaryDistance.swift`; new `Tests/SheepFenceTests/DistanceGeometryTests.swift`; `GeometryTests.swift` only if needed; own review report |
| pi | `Storage/SnapshotStore.swift`, `Storage/CoreDataSnapshotStore.swift`, `Sources/HTTPDownloader.swift`, `Sources/SnapshotSource.swift`, `Location/SamplingPolicy.swift`, `Location/CoreLocationProvider.swift`; new `Storage/StoreLeaseRegistry.swift`; `StoreTests.swift`, `SourceTests.swift`, `LocationProviderTests.swift`, new `SamplingConfigurationTests.swift`, `StoreLeaseTests.swift`; own review report |

All source paths above are relative to `Sources/SheepFence/` unless prefixed Tests.
Codex makes any shared public-type edits inside pi-owned files during phase 1, then
explicitly hands them over; after handoff Codex stops editing them until pi freezes.
No one edits `Package.swift`, fixtures or build settings without coordinating ownership.
Codex alone stages/commits integration. No agent pushes or tags as part of this plan.
Reviews are read-only except the reviewer's own report; findings go to the author to fix.

## Phase 0 — Approval and baseline (Codex)

- [ ] Obtain approval of API decisions: pure evaluate/stateful submit, distance model, GPS loss semantics, fixed/adaptive defaults, bounded events and deployment scope.
- [ ] Read applicable AGENTS instructions, confirm terminal identity/cwd, HEAD and existing changes; record in `docs/implementation/sdk-progress.md`.
- [ ] Run baseline `swift test --scratch-path .build/sdk-codex` and record failures separately from new regressions.
- [ ] Create an ownership/status table in sdk-progress.md with task, owner, reviewer, dependencies, state, evidence and blocking findings. States: queued, working, ready-for-review, changes-requested, approved, integrated, verified.

**Gate:** user-approved API and a known baseline. An existing failure must be understood, not hidden in later results.

## Phase 1 — Contract freeze (Codex; reviewed by OpenCode and pi)

API plan: Task 1, plus the interface portions of Tasks 2–5.

- [ ] Write `docs/implementation/sdk-contracts.md` with exact public types, defaults, constructors, enum cases and actor isolation. Pin EvaluationBatch field names (`evaluatedAt`, `sampleTimestamp`, `datasets`, `results`) and error cases; examples must match.
- [ ] Freeze internal handoffs: explicit distance estimate plus conservative adapter; store summary/removal result and lease acquire/release; bounded source error normalization; sampling mode/settings; provider stop/lifetime behavior.
- [ ] Define store path canonicalization for existing and new files, alias/symlink handling, and lease release on failed open/cancellation/deallocation. Test process-local duplicate opens; explicitly exclude cross-process locking.
- [ ] Land additive value types/configuration first, preserving a compiling current facade. Public protocol breaking signatures and call-site migrations switch together in phase 3; do not add placeholder fatalError/default-success methods just to pass compilation.
- [ ] Run external-import contract tests. If complete new-facade tests cannot yet compile, keep them as documented assertions until phase 3, not a broken test target or silently skipped test.
- [ ] Both agents independently review the written signatures and additive code for their component needs. Codex resolves all blocking disagreements and records the frozen contract version before phase 2.

**Gate:** focused contract tests pass; both agents report no blocking interface ambiguities. Contract changes after this gate require an explicit coordinator update to both agents before coding continues.

## Phase 2 — Parallel implementation

### C1 — Engine and state mechanics (Codex)

Dependencies: contract gate. API plan Tasks 2 and 4, engine portions of Task 3.

- [ ] Separate pure evaluation from monitoring ingestion and verify query calls never change baselines.
- [ ] Implement timestamp ordering, availability/freshness gap reset and historical confirmations. Test outside → no GPS/expiry → inside gives baseline, not entered; test gap without state() reads.
- [ ] Implement atomic current-state snapshots, latest evaluation reporting and registration-before-return.
- [ ] Implement independent bounded streams: explicit overflow failure, no silent transition dropping, cancellation cleanup and subscriber lifetime.
- [ ] Prepare engine catalog/deletion and public distance adapters against frozen component signatures; activate these when reviewed implementations arrive.
- [ ] Run engine/event tests using `.build/sdk-codex`; record exact cases/counts and unresolved findings.

### O1 — Distance geometry (OpenCode)

Dependencies: contract gate. API plan Task 2a geometry portion.

- [ ] Add analytic interior/exterior/edge/hole/component tests, explicit unsupported-envelope tests and finite nonnegative distance checks.
- [ ] Return explicit supported/unsupported estimates. Preserve conservative monitoring through the frozen internal adapter; no exposed fabricated zero.
- [ ] Validate supported zero versus unsupported result and dateline/local-envelope behavior. Do not alter containment semantics or introduce global-geodesic claims.
- [ ] Run `swift test --scratch-path .build/sdk-opencode --filter 'DistanceGeometryTests|GeometryTests'`.
- [ ] Freeze owned files and report summary, test evidence and assumptions in `docs/implementation/reviews/sdk-opencode-implementation.md`.

### P1 — Store and lifetime (pi, before P2)

Dependencies: contract gate. API plan Task 3 component portion.

- [ ] Implement transactional remove, summaries and the process-local store lease registry, with failure rollback and deterministic pending install/remove ordering tests.
- [ ] Test failed initialization and cancellation release reservations; alias paths cannot open the same store twice. No destructive recovery of corrupt stores.
- [ ] Expose the frozen internal operations only; Codex integrates engine readiness, observations and events.
- [ ] Run `swift test --scratch-path .build/sdk-pi --filter 'StoreTests|StoreLeaseTests'` and report readiness.

### P2 — Sources, sampling and provider (pi)

Dependencies: P1 and contract gate. API plan Task 5 component portion.

- [ ] Implement shared Data/file/HTTPS cap and structured transport errors, preserving redirect rejection and no credential leakage.
- [ ] Implement fixed sampling and explicit adaptive mode using frozen public types. Verify initial settings applied before provider start.
- [ ] Verify missing/denied/restricted/services-disabled/reduced-accuracy mappings, callback generation isolation and shutdown behavior with injected controls; do not depend on the Mac's actual authorization state.
- [ ] Test cancellation boundaries in source/store components; Codex verifies the combined commit boundary during integration.
- [ ] Run `swift test --scratch-path .build/sdk-pi --filter 'SourceTests|LocationProviderTests|SamplingConfigurationTests|StoreTests|StoreLeaseTests'`.
- [ ] Freeze owned files and write `docs/implementation/reviews/sdk-pi-implementation.md`.

Shared checkout rule: tests may compile files being changed elsewhere. Coordinate short
source-freeze windows before meaningful test runs. Separate scratch paths prevent build
DB contention but do not make mutable sources isolated. If another task breaks the build,
record the exact file/diagnostic and notify Codex; do not patch another owner's files.

## Phase 2R — Independent component review

Begin each review only after the author announces a freeze and no in-flight mutation.

| Author / component | Reviewer | Required independent checks |
|---|---|---|
| OpenCode / distance | pi | Unsupported vs zero, hole/component distances, local range, unchanged monitoring conservatism |
| pi / storage | OpenCode | Rollback, deletion vs concurrent installs, lease races and failure cleanup |
| pi / sources/provider | OpenCode | Byte caps, cancellation, error mapping/redaction, fixed/adaptive startup, stale callbacks |
| Codex / engine/events | pi, then OpenCode | Pure-query isolation, GPS recovery baseline, stream ordering/overflow, atomic snapshot/revision semantics |

Reviewers reproduce at least one boundary or race case relevant to the component, then
run focused suites under their own scratch path. They report actual pass/fail evidence,
not merely agreement with author counts. Reviewer findings go to the author; repeat
focused review only for fixes or newly affected behavior. No author self-approves a gate.
Reports: `sdk-pi-review.md` and `sdk-opencode-review.md` under `docs/implementation/reviews/`.

## Phase 3 — Public integration (Codex)

Dependencies: all components frozen and component blockers resolved. API plan integration portions of Tasks 1–5.

- [ ] Take exclusive integration ownership; tell both agents to remain read-only.
- [ ] Switch protocol/facade and consumer tests together to pure EvaluationBatch evaluation, submit, throwing events, state, discovery, removal and distance.
- [ ] Wire lease lifecycle, parent-directory creation, restore, Data import, normalized errors, configuration defaults and old open overload forwarding. Old overload explicitly selects adaptive configuration supplied by its caller; it must not silently select the new fixed default.
- [ ] Test cancellation before durable commit preserves old state and cancellation after commit begins reports the completed outcome. Test no provider/lifecycle cancellation can misreport a committed install as rolled back.
- [ ] Add public API distance tests, atomic snapshot/revision tests and full real-import deletion/expansion/concurrent-failure acceptance sequence.
- [ ] Update all existing tests that intentionally relied on stateful evaluate to use active hostProvided + submit. Preserve former behavior coverage rather than weakening assertions to make migration pass.
- [ ] Run complete package tests, public-consumer compilation and `git diff --check`. Both reviewers inspect the final integrated paths, not just their prior component patch.

**Gate:** full suite passes, both peers approve final integration and the published API matches the frozen contract. Record the exact tree/commit validated; repeat affected checks after changes.

## Phase 4 — Consumer documentation and physical validation

Codex writes; OpenCode reviews API examples and distance limitations; pi reviews lifecycle/GPS/error guidance. API plan Task 6.

- [ ] Build DocC, update README and add `docs/sdk-migration.md` covering evaluate→submit, batch results and throwing stream consumption. Compile tutorial code in public-import tests; never treat formatted snippets as validated code.
- [ ] Update the foreground host for query, distance, state display, GPS-unavailable UI and monitoring. Display historical last confirmation with its time, never as current membership.
- [ ] Build/run a clean consuming target without @testable. Verify its dependency is the public SPM product and no app signing team or device identifier is committed.
- [ ] Run full package and iOS simulator suites, then physical-device Release host validation. Use the installed compatible Xcode/device tools explicitly; discover current destinations instead of assuming UUIDs.
- [ ] Physical checks: install/launch, synthetic 100-area correctness and timing, distance known-fixture checks, request permission only via the host, start/stop/restart, foreground/background, denied and precise/reduced accuracy when the user can perform the necessary OS changes. Mark unavailable scenarios as untested, not passed. No real location traces are stored/uploaded.
- [ ] Rerun benchmark after final SDK changes; report P50/P95/P99 and measurement boundary. No field energy SLA or universal latency threshold is inferred.
- [ ] Refresh acceptance/progress docs with per-case evidence and remaining field gates. Have both peers review documentation against actual results.

Suggested commands (replace discovered simulator/device destinations before execution):

```sh
swift test --scratch-path .build/sdk-codex
swift test --scratch-path .build/sdk-opencode
swift test --scratch-path .build/sdk-pi
xcodebuild -list
xcodebuild -showdestinations -scheme SheepFence
# Then xcodebuild test with the selected simulator, separate derivedDataPath/resultBundlePath.
# Build the host with the user's local signing team supplied via command-line settings.
```

A full-suite run by each reviewer is the final verification gate, not a requirement to
rerun the entire suite after every small component edit. Record commands and outcomes.
If toolchain/availability blocks a gate, document it and continue independent work; never
claim completion from stale results.

## Dispatch messages to send only after approval

Send through the existing Herdr terminals using `hc send` (verify current CLI help and
multiline handling first). Each message contains the approved contract version, owned
files, dependencies, focused tests, report path and explicit stop-at-handoff instruction.
Do not send all phases at once.

**Contract review → t8 and t9**

> Read docs/superpowers/plans/2026-11-14-sdk-api.md, the dispatch plan, and docs/implementation/sdk-contracts.md. Review only: check signatures, GPS recovery, distance unsupported semantics and your component interfaces. Report blocking issues with exact contract references. Do not implement or edit shared files. Write only your assigned review report. Wait for the contract gate.

**O1 → OpenCode t9**

> Contract gate approved at [recorded version]. Implement O1 only under its exact ownership list. Add distance geometry boundary tests, preserve conservative monitoring behavior, use .build/sdk-opencode, and report evidence in sdk-opencode-implementation.md. Coordinate a source freeze before testing. No engine/facade/public contract edits, commits or pushes. Announce frozen files and await pi's review.

**P1/P2 → pi t8**

> Contract gate approved at [recorded version]. Implement P1 then P2 under the exact ownership list. Coordinate interface changes with Codex before touching shared types. Use .build/sdk-pi, report evidence in sdk-pi-implementation.md, and announce a freeze for OpenCode review. No engine/facade edits, commits or pushes. Stop at component handoff.

**Cross-review → designated reviewer**

> Review [frozen component/version] read-only against the approved API contract. Reproduce the assigned boundary/race cases and run focused tests under your scratch path during a coordinated freeze. Report blocking vs non-blocking findings with file/line, repro, expected/actual and command result. Do not fix the author's files. Await author fixes before the next review.

**Final integrated review → both peers**

> Review [integration tree/commit] including public consumer API, concurrency, GPS recovery, distance, source/store cancellation and documentation. Run the full suite independently with your scratch path. Verify prior findings were resolved. Report Approved or Changes requested with precise evidence; no edits outside your report, no pushes or release actions.

Bracketed values are populated from the live status log at dispatch time, not invented
in advance. If an agent stalls, inspect its terminal and report the blocker; do not run
another agent's implementation concurrently in its owned files.

## Finish and handoff

- [ ] Codex reports implemented APIs, independent review verdicts, exact tests/device observations, remaining field gates and any intentional breaking changes.
- [ ] User reviews the resulting SDK. Commit/push/version/license decisions are separate from this planning approval; no automatic tag or public release.

Approval of this plan authorizes the phase-0 onward implementation dispatch, not a claim
that unobserved GPS scenarios, field accuracy or energy acceptance have already passed.
