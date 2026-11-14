# OpenCode contract-gate review

**Verdict: Approved**

Reviewed `docs/implementation/decisions.md`, changed/new contracts (`Sources/SheepFence/Configuration.swift`, `GeofenceClient.swift`, `Models.swift`, `Engine/Clock.swift`, `Geometry/GeometryTypes.swift`, `Import/ValidatedSnapshot.swift`, `Location/LocationProvider.swift`, `Sources/SnapshotSource.swift`, `Storage/SnapshotStore.swift`) and `Tests/SheepFenceTests/{ContractTests.swift,Support/PreparedSnapshotBuilder.swift}` against approved plan rev 3 (importer/geometry usability + spec semantics). Shared checkout not modified.

- **Spec semantics:** `query(coordinate:in:) -> GeometryQueryResult` binds binary membership+revision to one snapshot; `contains` is explicit Bool convenience without revision attribution. `RegionEvaluation`/`DatasetChange` remain the CLLocation/reevaluation carriers (uncertainty/unavailability, affected/removed IDs, evaluations empty but affected IDs retained when no current sample) — consistent with no data-driven crossing/baseline fabrication. `SnapshotStore.commit -> SnapshotCommit` returns effective snapshot for unchanged/older-skip/conflict handling. Config/download policy require explicit age/limits; availability/source-mode/stream contracts match decisions.
- **Importer/geometry usability (Tasks 1-2):** Internal validated types are sufficient (`ValidatedSnapshot`, `Region`, `RegionGeometry` polygons/rings shell-first, per-polygon `RegionBounds` for split-dateline/candidate work, `Coordinate.isValid`). `GeofenceError.invalidSnapshot(regionID:path:reason:)` (+ `unsupportedSchema`) can carry required feature/path diagnostics. Fixed APIs in decisions (`GeoJSONDecoder.decode`, `Geometry.contains`, `Geometry.distanceToBoundary`) are usable with these types; `Geometry` namespace/type to be added in Task 2 implementation as specified.

No blockers.

## Addendum — minor gate additions verified

**Verdict: Approved (no blockers).** Inspected `Sources/SheepFence/Engine/MonitoringSession.swift` and updated `Tests/SheepFenceTests/ContractTests.swift` (plus compile-time client surface/availability coverage). Existing geometry/import interfaces unchanged.

- `MonitoringSession`: same-mode start is idempotent without generation bump; active mode change throws `sourceModeConflict`; stop is idempotent and transitions bump generation; `requireHostSource()` rejects `sdkManaged` while permitting host-provided/single-shot-not-started usage — matches source-mode/session semantics.
- `DatasetReadiness`: ready-empty installed dataset accepted, missing expected dataset and no-installed-datasets reported via `datasetNotReady(...)` as specified.
- `ContractTests`: exercises above invariants, confirms reduced accuracy is not unavailability, and includes compile-time `GeofenceClient` surface checks (`contains`/`query`/`startMonitoring`/`updateAvailability`/`stopMonitoring`).
