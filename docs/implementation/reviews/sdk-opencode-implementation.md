# SDK O1 Implementation Report (OpenCode / distance geometry)

**Status:** Frozen, ready for pi review handoff. No commits/pushes. No shared API/engine/facade edits.

## Scope (owned files only)
- `Sources/SheepFence/Geometry/BoundaryDistance.swift`
- `Tests/SheepFenceTests/DistanceGeometryTests.swift` (new)
- `Tests/SheepFenceTests/GeometryTests.swift` — unchanged (existing suite still passes)

## Implementation
- Added `Geometry.boundaryDistanceEstimate(_:in:) -> BoundaryDistanceEstimate`:
  - Returns `.approximateMeters(Double)` for supported local-model distances (nearest edge across all rings/components, including holes; local equirectangular projection at query latitude with longitude unwrapped near query for dateline-local cases).
  - Returns `.unsupported(.outsideLocalModelRange)` for invalid/non-finite query coords, |lat|>80°, or any ring vertex outside 1° latitude / 1° unwrapped-longitude of query (whole result unsupported; no partial/global claim).
  - Returns `.unsupported(.numericalFailure)` for non-finite/non-positive projection or computed segment distances / no valid segments.
  - Supported boundary/on-edge cases yield finite nonnegative meters (distinguishable from unsupported).
- Retained `Geometry.distanceToBoundary(_:in:) -> Double` as conservative adapter:
  - `.approximateMeters(m)` → `m`; `.unsupported` → `0` (never overstates separation), preserving existing monitoring/`GeometryOperations.distance` closure behavior.
- No containment semantics changes; `RegionDistanceResult`/public query wiring left to Codex integration as contracted.

## Test evidence
- Command: `swift test --scratch-path .build/sdk-opencode --filter 'DistanceGeometryTests|GeometryTests'`
- Build: succeeded (`Build complete!`).
- Result: **14 tests in 2 suites passed** (0 failures).
  - `GeometryTests` (7): existing coverage preserved (boundaries/holes, multi-polygon/signed, endpoint/axis distance, dateline candidate+distance, candidate conservatism, small polygon epsilon, hole-edge distance).
  - `DistanceGeometryTests` (7, new): interior/exterior/edge analytic distances; supported-zero vs unsupported distinguishable + adapter returns 0 for unsupported; hole-interior nearest hole edge and hole boundary; multi-component nearest boundary; dateline-local supported envelope; unsupported envelope cases (high latitude, distant vertex/query, far component) with adapter conservative; adapter parity for supported results.
- Notes: initial draft had 2 envelope-violating test fixtures (>1° geometry extent) causing expected unsupported results; fixtures adjusted to stay within supported local envelope while preserving intent. Final run green.

## Freeze / coordination
- Coordinated test windows with t7 (acknowledged C1 freeze, no in-flight mutations during their run; resumed after C1 complete).
- O1 files above are frozen pending pi review. Awaiting review findings via t7/reports; ready to address O1-owned issues if requested.
