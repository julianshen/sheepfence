# OpenCode plan review — 2026-11-14-sheepfence-implementation (final, rev 3)

**Inputs reviewed:** `docs/superpowers/plans/2026-11-14-sheepfence-implementation.md` (revision 3), `geofence-sdk-spec-v0.3.md`, scaffold (`Package.swift`, `Sources/SheepFence/*`, `Tests/SheepFenceTests/*`, `README.md`). No implementation or plan edits.

## Verdict
**Approved (final).** Plan is feasible and spec-consistent across scope, dependency ordering, three-agent ownership/cross-review, geometry/import, persistence/source/location behavior, and acceptance completeness. Revision 2 corrections remain in place; revision 3 additions are verified.

## Revision 3 additions verified (pi)

| Addition | Verification |
|---|---|
| Task 5 — no-op install event/state invariants (`:148`) | Spec-consistent. §3 defines same-revision identical bytes as success with no change, older version skipped, different-bytes same revision as conflict, and publishes `datasetChanged`/reevaluation only for adopted dataset changes. Requiring unchanged/older-skipped/conflict/failed installs to not publish `datasetChanged`, rebase/reset state/last-confirmed time, or change active geometry (except explicit install error), with engine tests proving no data-change/baseline/crossing event and preserved snapshot/confirmation, correctly enforces invariants and prevents spurious events/state churn. |
| Task 9 — representative field accuracy/latency/energy acceptance (`:193`) | Spec-consistent and completes acceptance. §8.1 requires real-device Release evidence and §8.1 notes accuracy/power thresholds should be decided from representative field/device data. The added protocol (stationary boundary jitter + near/far routes, independent crossing times, varied accuracy/valid-unknown speed, adaptive vs fixed baseline, false/missed/late/uncertainty/delay/update-frequency/energy metrics, permission/privacy handling, documented method/limits, product-owner thresholds, explicit pending when site/device/thresholds unavailable, assigned peer responsibilities) provides actionable field evidence without inventing pass thresholds. |

## Revision 2 corrections (retained)

- **Candidate/uncertainty coverage:** Task 2 uses `accuracy+buffer`-expanded bounds union prior inside/confirmed states; raw point-only bbox miss cannot exclude uncertainty contact. Task 8 includes outside-bbox/touching-disk `boundaryUncertain` case with preserved confirmation, no crossings, zero-fetch assertion.
- **Import orientation/topology:** Task 1 uses ring position for role, accepts either winding on read with optional canonical normalization, never repairs topology by role change, tests reversed valid windings/malformed holes with exact paths, rejects unsplit antimeridian crossings.
- **Dataset-change semantics:** Task 4/5 publish adopted revision/affected-deleted IDs/reevaluation results in `datasetChanged`; rebase changed/new/re-enabled only with valid recent sample; remove deleted/disabled state; metadata-only preserves state; no standalone entered/exited/movement-baseline from data change; no fabricated baseline without valid sample (later confirmed observation may establish baseline). Covered cases include new/expanded/re-enabled/disabled/deleted/metadata-only/expired/startup-no-sample/stopped monitoring.
- **Revision-bearing query contract:** Task 0 freezes `query(coordinate:in:) -> GeometryQueryResult` from one snapshot, preserves Boolean `contains` convenience, reconciles §3 convenience exception, and requires contract tests (no separate revision lookup, empty/missing behavior).
- **Download policy/atomicity:** Gate 0/Task 6 reject redirects initially (incl. downgrade/same/cross-host/loops cases), no ambient cookies/credentials, caller-configured finite byte/time limits enforced during receipt incl. chunked/no Content-Length, cancellation never hands partial data, only complete bytes+metadata atomically to importer, prior snapshot preserved.
- **Host availability/mode contract:** Gate 0/Task 0/7 freeze host availability update API/protocols, source-mode exclusivity, hostProvided/sdkManaged paths producing `locationAvailabilityChanged` + baseline reset on loss, not-determined/denied/restricted/disabled handling, reduced accuracy reported but not treated as unavailable.

## Intentionally not adopted (spec-consistent)

- **No standalone baseline/enter/exit events from dataset imports; rebased results in `datasetChanged`:** Consistent with §3 (“資料改版引起的狀態差異只回報為資料變更…”). This avoids attributing redraw/data updates to user movement while preserving revision/reevaluation traceability.
- **`GeometryQueryResult` remains binary pure-coordinate containment; uncertainty in `RegionEvaluation`:** Consistent with §4 separation of binary geometry queries (given explicit coordinate) from mobile-location queries carrying timestamp/horizontal accuracy (`boundaryUncertain`/unavailable/confirmed behavior).

## Feasibility, ordering, ownership, acceptance

- **Dependencies/feasibility:** Wave ordering is coherent (Task 0 freeze → units/store/observation → atomic install/sources → provider/capacity harness → integration). Task 3 via Codex-owned `PreparedSnapshotBuilder` avoids premature production importer coupling.
- **Ownership/cross-review:** Three-agent split, file ownership, Codex-owned shared contracts/API, mandatory independent reviews with commit/content IDs, and serialized integration/build scratch paths are adequate controls.
- **Acceptance completeness:** §8 cases mapped to real importer/store/engine tests, §8.1 deterministic capacity/load/zero-fetch evidence, Release P50/P95 protocol, and field accuracy/latency/energy protocol are present; device/product-threshold-dependent gates correctly remain pending until evidence/decisions exist.

## Residual non-blocking notes

- Keep `GeometryQueryResult` binary and location uncertainty/unavailability in `RegionEvaluation`/observation models.
- Keep shared test builders/support under explicit Codex-owned paths.
- Field/Release performance gates must not be marked passed without agreed thresholds and actual device/site evidence.
