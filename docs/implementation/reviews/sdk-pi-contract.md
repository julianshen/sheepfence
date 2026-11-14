# pi contract review — sdk-contracts.md v1 (storage / source / sampling / lease)

**Verdict: Approved.** No blocking interface ambiguity remains for pi's components
(P1 store/lease, P2 source/provider, sampling types). Three non-blocking pins are
listed below with proposed defaults; Codex should record them in the contract or
counter before P1 lands. Reviewed docs: `docs/implementation/sdk-contracts.md`,
`docs/superpowers/plans/2026-11-14-sdk-api.md`, `2026-11-14-sdk-dispatch.md`.

**Reviewed state:** HEAD `eb8ccd3` plus Codex's uncommitted additive phase
(`SDKModels.swift`, `Models.swift`, `GeofenceClient.swift`, `LocationProvider.swift`,
engine helper rename, `SDKContractTests.swift`; 12 dirty paths, no commits by peers).
Reproduced Codex's gate claim under the pi scratch path:

```text
swift test --scratch-path .build/sdk-pi --filter 'SDKContractTests|ContractTests'
Test run with 8 tests in 2 suites passed after 0.001 seconds. Exit status: 0
```

## Verified against the landed tree

- **Public additions match the contract exactly.** `SDKModels.swift`: `EvaluationBatch`
  (field order `evaluatedAt/sampleTimestamp/datasets/results`), `DatasetSummary`,
  `RegionSummary`, `DatasetRemovalResult`, `MonitoringState`, `DatasetReadiness`
  (`noDatasets`/`missingRequired(Set<String>)`/`ready`), `BoundaryDistanceEstimate`,
  `DistanceUnsupportedReason`, `RegionDistanceResult` (throwing init rejects
  negative/nonfinite estimates), `SourceFailure` — all with public immutable
  properties, inits, `Equatable`/`Sendable`. `Models.swift` gains
  `sourceFailed(SourceFailure)`, `storeAlreadyOpen`, `eventBufferOverflow`.
  `LocationSourceMode` is now `Equatable`; internal helper renamed
  `DatasetReadinessCheck` with all call sites updated.
- **Source pins are correctly resolved.** `unsupportedScheme` (no URL) joins
  `SourceFailure`; non-HTTPS remote maps there, local missing/unreadable maps to
  `fileRead`, `redirectRejected` carries no URL. This closes a real redaction gap:
  current `HTTPDownloader.readHTTPS` throws `unsupportedSource(finalURL)` with the
  redirect *target* URL, which can bear credentials — the new source must not.
  Direct `GeofenceError.sourceFailed` throwing with no engine double-wrap is the
  right normalization point. Keeping legacy `downloadFailed`/`unsupportedSource`
  cases for compatibility is fine; no new source path may produce URL-bearing errors.
- **GeofenceEvent additive cases landed** (`stateSnapshot`, `evaluated`,
  `datasetRemoved`) with `DatasetChange` gaining a public init — payload
  constructors all public as required.
- **Store handoff is implementable.** Current `SnapshotStore` is internal with
  `loadCommittedSnapshots` + serialized `commit -> SnapshotCommit`
  (compare/replace/save under one queue, `context.rollback()` on failure), so
  transactional `removeDataset` (commit before return, wasPresent semantics) fits
  the existing pattern. No fake-success default extension is acceptable — removal
  must be a hard protocol requirement.
- **Sampling split is coherent.** `SamplingPolicyConfiguration` is already public
  with a throwing init (uncalibrated placeholders documented); adding
  `LocationSamplingConfiguration` + `SamplingMode` in pi-owned
  `SamplingPolicy.swift` while `SamplingPolicy`/`SamplingSettings` stay internal
  matches the facade's closure-selection design. Codex's configuration additions
  (`downloadPolicy: .standard`, `sampling: .fixed(.standard)`) correctly wait for
  these types; the 4-argument `open` forwarding to explicit adaptive policies must
  not silently pick the fixed default (contract already pins this).
- **Provider unchanged.** `LocationProvider.swift` touched only for `Equatable`;
  `onEvent/start/stop/apply` and generation handling preserved; pi edits only
  `CoreLocationProvider.swift`.

## Pins requested (non-blocking; proposed defaults)

1. **`StoreLease` visibility and `acquire` errors.** Keep `StoreLease`,
   `acquire(for:)` and the registry internal (hosts only see `storeAlreadyOpen`
   from `open`). Pin: duplicate canonical URL → `GeofenceError.storeAlreadyOpen`;
   non-file store URL → `invalidConfiguration`. Order in `open`:
   canonicalize URL → acquire lease → create parent directories → init store;
   lease release idempotent + deinit covers every throw path.
2. **`LocationSamplingConfiguration` validation.** Propose
   `distanceFilterMeters` finite ≥ 0, `desiredAccuracyMeters` finite > 0,
   throwing `invalidConfiguration` otherwise. Core Location sentinel values
   (`kCLLocationAccuracyBest` = -1) are intentionally not representable at this
   meters-scale API — state that in DocC.
3. **Parent-directory creation ownership.** Propose `CoreDataSnapshotStore.init(url:)`
   creates missing parent directories (making the api plan's "created by `open`"
   hold transitively) so the facade only canonicalizes and leases. Codex counters
   if integration prefers the facade to own it.

## Notices for Codex (no action needed by pi)

- **`removeDataset` as a protocol requirement breaks two Codex-owned test
  doubles:** `TestSnapshotStore` (`Tests/SheepFenceTests/EngineIntegrationTests.swift:7`)
  and `StoreReadProbe` (`Tests/SheepFenceTests/AcceptanceTests.swift:5`). Per
  contract, pi will not edit these files; expect transient build breakage during
  P1 and implement removal stubs in the doubles at integration.
- Removal ordering pin "sorted datasetID/featureID" matches the existing internal
  `idOrder` (featureID first, then datasetID); for a single-dataset removal the two
  orderings coincide, so use `idOrder` as the canonical sort.
- With fixed sampling, the facade's per-sample `engine.nearestBoundary` round-trip
  is unnecessary work; Codex may skip it when the selection closure ignores distance.

Approval covers the contract gate only — not the pending P1/P2 implementations,
which remain gated on Codex's explicit implementation release.
