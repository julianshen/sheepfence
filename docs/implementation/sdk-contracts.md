# SDK contract freeze v1

User approved SDK API/dispatch plans on 2026-11-14. The plans govern external behavior. Current baseline eb8ccd3. Codex owns all shared API/engine files. Additive types first; breaking facade/protocol switch occurs only after component freeze.

## Exact component interfaces

- OpenCode: add `Geometry.boundaryDistanceEstimate(_:in:) -> BoundaryDistanceEstimate`. Keep `distanceToBoundary(_:in:) -> Double` as conservative adapter returning 0 for unsupported. Existing GeometryOperations.distance closure stays Double so current tests/build remain valid. Codex adds public distance integration.
- pi store: add `SnapshotStore.removeDataset(id: String) async throws -> DatasetRemovalResult`. Real CoreData implementation commits before return; result IDs sorted datasetID/featureID. Test doubles need implementing; report them to Codex, do not edit their files. Do not supply a fake-success default protocol implementation.
- pi lease: `final class StoreLease: Sendable` with `static func acquire(for url: URL) throws -> StoreLease`, `let url: URL` canonicalized; `func release()` idempotent plus deinit release. Synchronous process-local lock protects registry, lease owns unique token so old release cannot remove new lease. Canonicalize parent symlinks for nonexistent file. Facade obtains lease before create/open, retains until engine/store tasks finish; Codex integrates lifetime.
- pi source: keep SnapshotSource.read(from:) and add `DownloadPolicy.standard` (5_000_000 bytes,30sec). Data size cap is enforced by Codex engine. `SourceFailure: Error, Equatable, Sendable` public enum cases `unsupportedScheme`, `httpStatus(Int)`, `timeout`, `byteLimitExceeded(maximumBytes: Int)`, `redirectRejected`, `network`, `fileRead`. GeofenceError adds `.sourceFailed(SourceFailure)`; retain old downloadFailed deprecated if necessary. Source implementations throw GeofenceError.sourceFailed directly (no double wrapping). Non-HTTPS remote schemes map to unsupportedScheme without retaining the URL; local missing/unreadable files map to fileRead. Cancellation remains CancellationError. Do not leak URL credentials/body/raw NSError.
- pi sampling: `LocationSamplingConfiguration` public Sendable/Equatable with distanceFilterMeters, desiredAccuracyMeters and throwing init; `.standard` 10m/10m. `SamplingMode` public enum `.fixed(LocationSamplingConfiguration)`, `.adaptive(SamplingPolicyConfiguration)`. Keep SamplingPolicy and SamplingSettings internal. Codex implements closure selection in facade; pi implements public sampling types in SamplingPolicy.swift and tests.
- pi provider: preserve onEvent/start/stop/apply protocol and existing epoch handling. Report lifetime cleanup needs to Codex; do not edit LocationProvider.swift.

## Codex-owned public additions

EvaluationBatch(evaluatedAt: Date,sampleTimestamp: Date,datasets:[DatasetMetadata],results:[RegionEvaluation]); immutable public properties/init, Equatable/Sendable. DatasetSummary(metadata,regionCount,enabledRegionCount); RegionSummary(id,revision,name,enabled,priority); DatasetRemovalResult(datasetID,removedRegionIDs,wasPresent); MonitoringState(mode,readiness,availability,datasets,evaluations) with public initializers.

DatasetReadiness enum noDatasets/missingRequired(Set<String>)/ready moves from internal helper; rename helper DatasetReadinessCheck. LocationSourceMode becomes Equatable. Distance enums and RegionDistanceResult match approved plan; invalid negative/nonfinite estimate initializer throws invalidConfiguration.

New GeofenceError: sourceFailed(SourceFailure), storeAlreadyOpen, eventBufferOverflow. Existing invalidConfiguration covers bad buffer/settings. Public GeofenceConfiguration adds downloadPolicy=.standard,sampling=.fixed(.standard). Keep existing configuration init source compatible. Existing 4-argument open forwards to explicit policies, adaptive sampling.

Events add stateSnapshot(MonitoringState), evaluated(EvaluationBatch), datasetRemoved(DatasetRemovalResult). All payload constructors public. Events registration throwing bounded AsyncThrowingStream, default 256. Slow subscriber gets explicit failure. Pure evaluate returns EvaluationBatch and emits nothing; submit requires active hostProvided. State includes expired projection and GPS loss preserves historical confirmation but resets baseline. See plan for details.

## Coordination

Phase 1 reviewers inspect this document and plans read-only before approval. Once approved Codex sends explicit implementation release. No parallel editing shared files, no commits/pushes by peers. Source freeze before focused testing. Use .build/sdk-opencode and .build/sdk-pi. Review reports under docs/implementation/reviews/sdk-*.

## Accepted pi review pins

StoreLease and registry are internal; duplicate canonical URL throws storeAlreadyOpen;
non-file store URL throws invalidConfiguration. Open order: canonicalize/acquire lease,
then create parent directories and initialize store. CoreDataSnapshotStore.init(url:)
owns directory creation so direct internal callers get consistent behavior. Facade owns
lease acquisition; lease retention must cover in-flight engine/store work.

LocationSamplingConfiguration validates finite distanceFilterMeters >= 0 and finite
desiredAccuracyMeters > 0; negative Core Location sentinel constants are not accepted.
Codex owns updating TestSnapshotStore and StoreReadProbe when removal lands. No fake
successful default removal implementation will be added to the protocol.
