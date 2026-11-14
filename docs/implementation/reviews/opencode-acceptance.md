# OpenCode read-only review: added AcceptanceTests oracles

**Scope:** `Tests/SheepFenceTests/AcceptanceTests.swift` new tests only:
- `campusGardenMovementAndJitterUseProductionGeometry` (`:14`)
- `holeAndSecondComponentQueryThroughStoreAndEngine` (`:46`)

**Execution (`.build/opencode`):** `swift test --filter AcceptanceTests` → **PASS** (5/5 tests in suite; includes 3 existing capacity/persistence tests).

## Oracle assessment

| Test | Spec/plan intent exercised | Assessment |
|---|---|---|
| `campusGardenMovementAndJitterUseProductionGeometry` | Bundled `campus-v3` fixture through real decoder/store/engine/geometry; overlapping regions (`garden` inside `campus`), movement creating first confirmed baseline outside garden then single `entered` for garden, repeat same confirmable sample produces no duplicate event, boundary jitter within `accuracy+buffer` yields `boundaryUncertain` while preserving last confirmed membership/timestamp/revision (§4/§8). | **Sound.** Uses production path (`runtime` wires `GeoJSONDecoder.decode`, `Geometry.contains/distance/isCandidate`, `CoreDataSnapshotStore(in-memory)`). Coordinates (10.001,20.002 outside garden; 10.003,20.002 inside garden ~111m from garden edge at lat20) with `accuracy=1`/buffer 0 give confirmed transitions; jitter points ±0.00001° (~±1.1m) from boundary with `accuracy=10` are well within uncertainty. Asserts exactly one event total (`entered garden`) and preserved `lastConfirmed` from 1102 — correctly prevents duplicate enters/crossings from repeats and uncertainty. |
| `holeAndSecondComponentQueryThroughStoreAndEngine` | Spec §2/§4/§8 geometry semantics through real decoder/store/engine: hole interior `outside`, hole boundary `inside`, MultiPolygon second component `inside` (binary geometry query). | **Sound.** Valid closed rings, shell/hole/component topology, installs JSON via production decoder/store. Query points: (10.003,20.003) inside hole → `outside`; (10.002,20.003) on hole boundary → `inside`; (10.025,20.005) inside second polygon → `inside`. Exercises `query`/revision-bearing geometry path over committed snapshot. |

## Notes (non-blocking)

- First test ends by emitting `servicesDisabled` availability to terminate event collector; it intentionally validates garden jitter/enter behavior rather than full campus exit/unavailable lifecycle.
- Tests complement existing 100x100 capacity, overlap transition-count, and bundled persistence/reopen/invalid-replacement acceptance coverage.

**Verdict:** Added oracles are correct and provide useful production-pipeline coverage for spec examples; no changes requested.
