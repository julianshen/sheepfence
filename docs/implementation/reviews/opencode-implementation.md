# OpenCode implementation review/report — Tasks 1-2 (+ follow-up fixes/reviews)

**Scope (owned only):** `Sources/SheepFence/Import/{GeoJSONDecoder,GeometryValidator,ImportDiagnostic}.swift`, `Sources/SheepFence/Geometry/{Bounds,Containment,BoundaryDistance,SegmentPredicates}.swift`, `Tests/SheepFenceTests/{ImportTests,GeometryTests}.swift`, `Tests/SheepFenceTests/Fixtures/Geometry/*`. No shared contract/type files edited. No commits made.

## Status
- **Task 1 (strict importer + topology):** implemented and focused tests passing.
- **Task 2 (containment + conservative local meter distance + candidate prefilter):** implemented and focused tests passing, including follow-up fixes for explicit local distance envelope/wording and pure coordinate-linear wide-polygon containment.
- **Cross-review (findings only, no edits):** `Engine/GeofenceEngine.swift`, `Engine/ObservationState.swift`, `Storage/CoreDataSnapshotStore.swift`, and later-added `SheepFenceClient.swift`/`ClientLifecycleTests.swift` reviewed for spec/concurrency/lifecycle; findings below.

## Implementation summary

### Import / topology
- `GeoJSONDecoder.decode(_:)`: strict JSON/root/FeatureCollection/`geofenceSchema==1`/dataset/feature parsing; rejects wrong types, missing/empty IDs, duplicate feature IDs, nonpositive/nonintegral revisions, wrong optional-property types, missing/non-object `properties`, bool-as-number misuse (CFBoolean identity), exact integer conversion for revision/priority. `generatedAt` requires RFC3339 UTC ending `Z` with strict format + calendar-component round-trip validation (rejects normalized invalid dates). Retains exact `sourceBytes` and SHA-256 in `ValidatedSnapshot`.
- `GeometryValidator`: Polygon/MultiPolygon only; ring position defines role (shell first, holes after). Validates finite in-range `[lon,lat]` pairs with exact count==2, strict ring closure equality, antimeridian split rule (`|Δlon| > 180°` rejected), >=3 distinct noncollinear vertices (scale-aware), no self-intersection/touching, hole inside shell, holes not outside/touching shell, holes not overlapping/touching each other. Accepts either winding and normalizes to canonical (shell CCW, holes CW) while preserving closed rings and roles. Returns per-polygon `RegionBounds` from shell. Diagnostics include feature ID and stable JSON paths (MultiPolygon uses per-polygon rings path without duplicated `.coordinates`).
- `ImportDiagnostic.invalid(...)` maps to `GeofenceError.invalidSnapshot(regionID:path:reason:)`.

### Geometry
- `Geometry.contains(_ point: Coordinate, in geometry: RegionGeometry) -> Bool`: pure GeoJSON coordinate-linear containment in raw ring coordinates (preserves valid wide polygons, e.g. edges spanning longitudes with all per-edge `Δlon <= 180°`) using scale-aware boundary detection + ray casting. Also checks consistent periodic translated polygon copies for split components near ±180° without changing raw interior semantics. Outer/hole boundaries treated as inside; hole interiors outside; any MultiPolygon component hit returns inside.
- `Geometry.distanceToBoundary(_ point: Coordinate, in geometry: RegionGeometry) -> Double`: nearest edge distance over all rings/components using local equirectangular projection at query latitude with longitudes unwrapped near point. **Explicit local support envelope (neighborhood-scale):** `|point latitude| <= 80°` and every ring vertex within `1°` latitude and `1°` unwrapped longitude of the query point. Outside this envelope, or for invalid/unsupported mapping, returns `0` (**uncertain; conservative lower bound, not an overestimate of separation**). This is an approximate local-meter model, **not rigorous global geodesic correctness**. Datasets are **not rejected** for distance-envelope limits; callers must combine with candidate/uncertainty handling and must not treat `0`/approximate results as proof of safe separation.
- `Geometry.isCandidate(_ point: Coordinate, radiusMeters: Double, bounds: [RegionBounds]) -> Bool` (static, conservative): returns `true` whenever uncertain/unsupported; `false` only when point+radius cannot intersect any bound under the local meter/lat-lon margin model (including periodic longitude interval checks near ±180°). High-latitude/large-margin/invalid/nonfinite cases remain conservative.
- `GeometryBounds.polygonBounds` helper present.

## Measured assumptions / numeric limits
- **Projection/model:** local equirectangular meters (`111132 m/deg lat`, `111320*cos(lat) m/deg lon`) for distance/candidate margins; coordinate-linear edge semantics preserved. Not geodesic and not globally rigorous.
- **Distance conservatism/envelope:** `distanceToBoundary` is only a local neighborhood approximation within the explicit envelope above; outside it returns `0` as an uncertain conservative lower bound (never presented as overestimated separation). `isCandidate` returns `true` for `|lat| > 85°`, very small/invalid lon scale, `lonMargin >= 180°`, invalid/nonfinite inputs, or oversized bound latitude span. Engine must combine candidate+distance+uncertainty and still emit accurate outside evaluations for safely excluded points (per integration instruction).
- **Containment semantics:** pure coordinate-linear containment in raw coordinates for valid imported polygons (including wide non-dateline-crossing polygons); periodic copy checks used only as whole consistent translations for split-near-dateline cases.
- **Predicate tolerance:** scale-aware orientation/collinearity/boundary tolerances (`~64*ulp*scale + 1e-18*scale`) replace fixed area epsilon; importer signed-area accumulation translated to first vertex for stability. Accepts valid tiny polygons (e.g. review regression) while keeping strict topological rejection and exact ring closure.
- **Ring closure:** import requires exact coordinate equality of first/last positions; query boundary handling uses separate scale-aware tolerance.
- **Periodic handling:** candidate uses periodic longitude interval checks near ±180°; containment has periodic-copy handling for split components; distance unwraps longitudes near query point. Unsplit crossing edges rejected at import.
- **Not verified/measured:** geodesic accuracy, error bounds outside/near envelope limits, high-latitude real-world behavior beyond conservative fallbacks, or performance P50/P95 (out of Task 1-2 scope; requires device/release/field evidence per plan). Existing capacity data are neighborhood-scale per region.

## Focused test evidence (exact)

Environment: `swift test --scratch-path .build/opencode --filter <suite>` (macOS arm64e, Swift Testing; XCTest harness reported 0 XCTest cases per filtered run as usual).

| Command | Result |
|---|---|
| `swift test --scratch-path .build/opencode --filter ImportTests` | **PASS** — `✔ Test run with 7 tests in 1 suite passed after 0.005 seconds.` |
| `swift test --scratch-path .build/opencode --filter GeometryTests` | **PASS** — `✔ Test run with 7 tests in 1 suite passed after 0.001 seconds.` |
| `swift test --scratch-path .build/opencode --filter ReviewRegressionTests` | **PASS** — `✔ Test run with 8 tests in 1 suite passed after 0.007 seconds.` (Codex-owned, run unmodified; includes `coordinateLinearWidePolygonPreservesInterior`) |

Notes: Earlier in-progress failures encountered and resolved during development: `ImportTests` helper arg-order/fixture-lookup issues, fixed-epsilon tiny-polygon rejection, and query-relative unwrap excluding valid wide raw polygon interior. No unresolved failures in owned/focused suites.

## Cross-review findings (no edits made)

### `Sources/SheepFence/Storage/CoreDataSnapshotStore.swift`
- **Low — commit ordering depends on caller ordering, not durable compare order:** `commit(_:)` awaits `beforeCommit` *before* enqueuing serialized work on `queue`. With concurrent callers and async interceptors (or any future pre-queue suspension), serialized compare/save blocks may enqueue in completion order rather than call order. Correctness is preserved by revision checks inside the serialized block, but interleavings like rev4/rev5 can produce counterintuitive “older skipped” outcomes depending on scheduling. Consider moving compare+interceptor+save sequencing policy entirely inside the serial queue/critical section if call-order linearization is required. (Production no-op interceptor makes this mostly theoretical.)

### `Sources/SheepFence/Engine/GeofenceEngine.swift`
- **No blocking spec/concurrency defect found in reviewed paths.** Install publication is serialized through `installTail` and only applies `outcome == .installed` with effective snapshot; no-op/older-skip/conflict do not mutate active snapshots/state/events. Dataset-change rebases affected enabled regions from `recentSample` only when valid/available, removes deleted/disabled state, emits `datasetChanged` payload (affected/removed IDs, evaluations possibly empty when no valid sample) without data-driven crossing/baseline events. Observation invalid/out-of-order handling and reset behavior align with decisions reviewed. Candidate prefilter is treated conservatively (non-candidate path still runs state transition with outside membership and non-certifying distance/radius), compatible with “accurate outside evaluations for safely excluded points”.
- **Note (integration dependency):** engine relies on `geometry.candidate`/`geometry.distance` conservatism contract (false only when proved safe; distance not a safe-separation proof when unsupported/uncertain). Implemented `Geometry.isCandidate`/`distanceToBoundary` follow this, but any future optimization must preserve it.

### `Sources/SheepFence/Engine/ObservationState.swift`
- **No blocking defect found.** Nonfinite/non-separating observations (`!(distance.isFinite && radius.isFinite && distance > radius)`, equality treated uncertain) yield `boundaryUncertain` without mutating confirmed state/events. Confirmed observations update state, emit baseline only on first confirmation, and emit entered/exited only on actual membership change.

### `Sources/SheepFence/SheepFenceClient.swift` + `Tests/SheepFenceTests/ClientLifecycleTests.swift` (read-only, added after prior report)
- **Async lifecycle serialization:** `serializeLifecycle` chains operations onto `lifecycleTail` (await previous then run), so start/stop/install-refresh paths are serialized on the `@MainActor` facade despite async engine calls. `installSnapshot` performs engine install first, then serializes `refreshProvider()` to reconcile SDK-managed acquisition with possibly changed enabled regions.
- **Provider generation invalidation:** facade tracks `generation` and `providerRunning`; `startMonitoring` (new session) and `stopMonitoring` bump generation, clear callbacks, stop provider as needed. `refreshProvider` captures `epoch`/`engineGeneration`, rechecks mode/generation/enabled state after async engine queries, and provider callbacks guard `mode == .sdkManaged && generation == epoch` before forwarding; engine receive/availability methods also validate engine generation. This prevents stale callbacks from prior sessions/modes applying after stop, mode conflict, or interleaved lifecycle transitions.
- **Explicit events:** start path delegates to engine which emits `locationAvailabilityChanged(.noLocation)` (or current reason) on new session start; provider location evaluation failures are caught and reported via `engine.reportEvaluationFailure(...)` emitting `evaluationFailed` (not silently discarded), matching decisions. Availability events are forwarded. Tests cover `noLocation` + `evaluationFailed`, host mode never starts provider/conflicts on mode change, SDK idempotence/stop callback clearing, empty dataset not acquiring location, and overlapping start/stop serialization (I did not rerun `ClientLifecycleTests` in this pass; review is source/read-only).
- **No blocking defect found in reviewed paths.** Minor note: if provider APIs are not themselves thread/MainActor-constrained beyond facade usage, correctness relies on facade-owned serialization/guards (appears consistent with protocol intent).

## Checkpoint status (final)
- **No further geometry/import edits necessary for checkpoint.** Owned/focused evidence above: `ImportTests` 7/7, `GeometryTests` 7/7, `ReviewRegressionTests` 8/8 passed (`.build/opencode`).
- **User/Codex reported (not rerun by me in this pass):** full package `57 tests / 9 suites` passed including wide-polygon regression; iOS 16 simulator source build passed.
- **Final geometry semantics reflected:** pure coordinate-linear containment in raw GeoJSON coordinates (with consistent periodic-copy handling for split-near-dateline cases, preserving wide raw interiors), plus explicit local distance envelope and uncertain conservative-lower-bound (`0`) fallback outside envelope — approximate local model, not rigorous global correctness, datasets not rejected.
- **Facade review complete (read-only):** `SheepFenceClient` lifecycle serialization, provider generation/callback invalidation, and explicit `noLocation`/`evaluationFailed` behavior reviewed; no blocking defect found in reviewed paths.
- **Not declared:** final SDK/device/Release/field acceptance; Pi provider review/choice still pending. Unowned files/tests not modified.
