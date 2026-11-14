# SDK OpenCode Contract Review (distance / API handoff)

**Verdict: Approved (no blocking issues).**

Reviewed read-only against current HEAD/additive state:
- `docs/implementation/sdk-contracts.md` (freeze v1, incl. accepted pi pins)
- `docs/superpowers/plans/2026-11-14-sdk-api.md`
- `docs/superpowers/plans/2026-11-14-sdk-dispatch.md`
- `docs/implementation/reviews/sdk-pi-contract.md`
- Landed additive contracts: `Sources/SheepFence/SDKModels.swift`, `Models.swift`, `GeofenceClient.swift`, `Configuration.swift`
- Current geometry baseline: `Sources/SheepFence/Geometry/BoundaryDistance.swift`, `GeometryTypes.swift`

## Distance handoff (O1) — clear and implementable

- **Explicit estimate API:** Add `Geometry.boundaryDistanceEstimate(_:in:) -> BoundaryDistanceEstimate` returning `.approximateMeters(Double)` or `.unsupported(.outsideLocalModelRange | .numericalFailure)`; keep existing `distanceToBoundary(_:in:) -> Double` as conservative adapter returning `0` for unsupported so current internal consumers/tests remain valid (`GeometryOperations.distance` closure remains `Double`).
- **No fabricated zero:** Supported boundary/on-edge zero must be distinguishable from unsupported (`.approximateMeters(0)` vs `.unsupported(...)`); unsupported model range and numerical nonfinite cases must never be surfaced as measured distance.
- **Semantics aligned with plan:** Coordinate-only, side-effect-free; membership/boundary rules include holes and multi-component minimum over shell/hole edges; `RegionDistanceResult` revision attributed to one committed snapshot; `distanceToRegionMeters == 0` when inside else boundary distance/nil when unsupported. `RegionDistanceResult` init already rejects negative/nonfinite estimates (matches contract).
- **Scope/ownership:** O1 owns `Geometry/BoundaryDistance.swift`, new `DistanceGeometryTests.swift` (and `GeometryTests.swift` only if needed); Codex owns public facade/protocol/query wiring, engine snapshot integration, `DistanceQueryTests`/acceptance/docs. Monitoring conservatism preserved via frozen internal adapter; no containment-semantics changes or global-geodesic claims.

## Public API / overall semantics — no blockers

- Pure `evaluate` vs stateful `submit`/provider ingestion split, GPS-loss/baseline-recovery rules, bounded throwing event streams with initial `stateSnapshot`, readiness/discovery/removal and source-failure normalization are coherent with frozen types and dispatch gates.
- `LocationSourceMode: Equatable`, additive event/result payloads, `SourceFailure` redaction cases, `DatasetReadiness`/`DatasetRemovalResult`/`MonitoringState`/`EvaluationBatch` shapes are consistent for integration.
- Component/test-doubles and shared-file ownership per dispatch (Codex integrates protocol breaks/test stubs; no parallel shared edits) are understood.

**Implementation gate:** Await explicit Codex release before O1 implementation/freeze; will coordinate source-freeze windows for meaningful `.build/sdk-opencode` test runs and report evidence in `docs/implementation/reviews/sdk-opencode-implementation.md`.
