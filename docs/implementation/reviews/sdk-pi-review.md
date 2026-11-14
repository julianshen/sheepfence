# pi independent review — O1 distance geometry (OpenCode)

**Verdict: Approved.** No blocking findings. One informational note for Codex's
public distance integration (Task 2a). Reviewed frozen files
`Sources/SheepFence/Geometry/BoundaryDistance.swift` and
`Tests/SheepFenceTests/DistanceGeometryTests.swift` plus OpenCode's
`sdk-opencode-implementation.md` report. No O1 source edits made.

## Independent reproduction

```text
swift test --scratch-path .build/sdk-pi --filter 'DistanceGeometryTests|GeometryTests'
Test run with 14 tests in 2 suites passed after 0.001 seconds.
```

Matches the author-reported 14/14. Reviewer scratch path; frozen sources, no
mutations. I additionally re-derived three fixture expectations analytically
rather than trusting the author's numbers:

- Interior point (10.002°, 20.005°) in rect(10–10.01, 20–20.01): nearest edge is
  the west edge, 0.002° longitude × cos(20°) ≈ 209 m — inside the asserted
  (150, 300) window.
- Hole interior (0.004°, 0.0035°) to hole bottom edge at 0.003°: 0.0005°
  latitude ≈ 55.7 m — inside (40, 70), confirming holes use the *nearest hole*
  edge, not the shell.
- Multi-component point (0.003°, 0.001°): ~0.001° ≈ 111 m from each component's
  inner edges — inside (80, 140), confirming minimum-over-all-components.
- Dateline case: unwrapped vertex −180.001° vs query −179.9992° → ≈ 89 m < 200 ✓.

## Required checks (dispatch Phase 2R, OpenCode/distance → pi)

- **Unsupported vs supported zero:** on-edge query returns
  `.approximateMeters(0)` (test `supportedZeroDistinguishableFromUnsupported`
  asserts ≈0), high-latitude/outside-envelope queries return
  `.unsupported(.outsideLocalModelRange)`. The conservative adapter maps
  unsupported → 0 and supported → its meters; the two states are never confused.
  ✓
- **Whole-result unsupported on distant geometry:** any vertex outside the 1°
  local box returns `.unsupported(.outsideLocalModelRange)` for the entire
  estimate even when another component/edge is nearby (test asserts the far
  component case; code path is a fail-fast guard in `localPoint`). Segments are
  convex combinations of enveloped vertices, so the envelope is sound for
  segments too. ✓
- **Hole and component distances:** all rings of all polygons participate,
  including hole edges; minimum over all segments incl. the implicit closing
  segment. ✓
- **Conservative monitoring adapter unchanged:** `Geometry.distanceToBoundary`
  delegates to the estimate and maps unsupported → 0 ("never overstates
  separation"), so the existing `GeometryOperations.distance` closure behavior
  (used by sampling/uncertainty) is preserved; `GeometryTests` passes untouched.
  ✓
- **No containment or geodesic-claim changes:** containment code untouched;
  projection documented as local equirectangular at query latitude with
  unwrapped longitudes; no global distance claims. ✓
- **Numerical safety:** degenerate segments handled without division by zero;
  non-finite projection/distance → `.unsupported(.numericalFailure)`; final
  result guarded finite ≥ 0. No fabricated values. ✓

## Informational note for Codex (non-blocking, no O1 change requested)

An empty or fully degenerate geometry (no polygons / all rings skipped) yields
`.unsupported(.numericalFailure)` rather than `.outsideLocalModelRange`. Both
are explicit unsupported states and the contract does not pin which reason; when
Codex wires the public `distance` query (Task 2a), either pin the expected
reason for that edge case or treat both unsupported reasons uniformly in public
tests, so the choice is stable rather than incidental.

Approval covers the O1 component; Codex's public `RegionDistanceResult` wiring
and public distance tests remain integration gates.

---

# pi independent review — Codex phase-3 integration (final)

**Verdict: Approved.** No concrete blockers. Reviewed the frozen integrated tree
read-only: `Engine/GeofenceEngine.swift`, `Engine/ObservationState.swift`,
`Engine/MonitoringSession.swift`, `Engine/CommitGate` usage,
`SheepFenceClient.swift`, `GeofenceClient.swift`, lease lifetime, public distance
wiring, README/`docs/sdk-migration.md`/DocC. Full independent run:

```text
swift test --scratch-path .build/sdk-pi
Test run with 138 tests in 24 suites passed after 31.467 seconds.
```

Actual reviewer counts: **138/138**, zero failures, on the frozen integrated
source (no source mutations by me).

## Verified integration seams

- **Engine/facade/events:** bounded `AsyncThrowingStream` per subscriber
  (`.bufferingOldest`), atomic initial `.stateSnapshot` yielded inside the actor
  at registration, explicit `GeofenceError.eventBufferOverflow` termination on a
  dropped event (buffered events drain before the error), invalid capacity →
  `invalidConfiguration` (recorded pin), stream teardown on termination and
  engine deinit. `stateSnapshot` emitted on start/stop and availability changes.
- **Pure evaluate vs stateful submit:** `evaluateOnce` touches no observation
  state, advances no timestamps, emits nothing, returns one-snapshot
  `EvaluationBatch` ordered priority-desc/id-asc with `lastConfirmed == nil`;
  `submit` requires active `.hostProvided` and publishes `.evaluated` for every
  accepted/rejected input including unchanged and uncertain.
- **GPS recovery semantics:** freshness gap > `maximumLocationAge` since the last
  accepted sample calls `state.interrupt()` (baseline reset) before accepting;
  availability loss also resets; first confirmable recovery sample emits
  baseline, never a synthetic crossing; expired projections in `state()` carry
  the last sample timestamp and do not generate events; not-ready datasets
  report readiness separately with no invented per-region observations.
- **Lease fix/lifetime:** engine retains the `StoreLease` through its lifetime
  (facade acquires before detached store init on `lease.url`; failed opens and
  cancellation release via deinit). Canonical-key stability across the
  parent-mkdir and file-creation windows is pinned by my
  `StoreLeaseTests.canonicalKeyIsStableAcrossParentAndFileCreation` (both drift
  windows assert `storeAlreadyOpen`; canonical URL identical after re-acquire).
  The `standardizingPath` drift root cause is fixed: realpath-resolved prefix is
  never lexically re-standardized; only the nonexistent suffix is normalized.
- **Distance public wiring:** single-snapshot attribution for membership and
  boundary estimate, throwing `RegionDistanceResult` init validation,
  `invalidCoordinate`/`datasetNotReady`/`regionNotFound` parity with `query`,
  unsupported estimates pass through as results (never fabricated zeros),
  disabled regions queryable when named. Public consumer flow
  (`SDKPublicConsumerTests.completeOfflineConsumerFlowAndExclusiveStore`)
  exercises duplicate-open exclusion end to end.
- **Cancellation/commit boundary:** install and removal serialize on
  `installTail` with a `CommitGate` — cancellation before durable commit throws
  without mutating state; once the durable save begins the outcome is published
  even on cancellation; no path can misreport a committed install as rolled back.
- **Removal integration:** removal joins the same transaction tail, commits
  durably before publication, emits `.datasetRemoved` (never exit events),
  clears per-region state/latest, updates readiness and provider activity.
- **Docs:** README + `docs/sdk-migration.md` correctly describe the pure
  `evaluate`/stateful `submit` change (stateful behavior explicitly called out as
  not preserved by `.results` renaming), DocC catalog present; fixed-mode facade
  skips the per-sample nearest-boundary round trip as recommended.

## Non-blocking observations (no action required)

1. `persistAndPublish` observes affected regions twice (once for the
   `DatasetChange.evaluations` payload, once to refresh `latest` for all enabled
   regions) with the same sample. Idempotent — second pass emits no events and
   overwrites `latest` with identical values; a brief comment would make the
   intent obvious for future readers.
2. `onTransactionQueued` is exercised only by `SDKCancellationTests`; fine as an
   internal hook, just noting it has no production wiring today.

Approval covers the integrated phase-3 tree as frozen at review time. Remaining
gates outside this review: physical-device validation and release decisions
(version/tag/license), per the dispatch plan.

## Post-integration addendum — SDKReplacementTests acceptance sequence

Reviewed Codex's final test-only addition `SDKReplacementTests.swift` (no source
changes): real `GeoJSONDecoder` + real SQLite store + real `HTTPSnapshotSource`
with a suspended failing transport. Verified read-only: the v3→v4 replacement
(deleting campus, expanding garden in one commit) rebases the confirmed
evaluation via `datasetChanged` without enter/exit crossings while a concurrent
download fails with `.sourceFailed(.network)`; publication order is protected by
the transaction tail; stop produces `locationAvailabilityChanged(.monitoringStopped)`,
never a synthetic exit; reopen durably shows revision 4 with only the garden
region. The deferred `failNow` prevents a hung continuation on early failure
paths. Test construction and assertions are correct.

Final reviewer full-suite run on the frozen tree:

```text
swift test --scratch-path .build/sdk-pi
Test run with 139 tests in 25 suites passed after 9.289 seconds.
```

**139/139, zero failures.** No further pi tests planned; remaining gates are
physical-device validation and release decisions (dispatch plan). One style
nit, non-blocking: `replacement`/`metadata` in the test could be `let` (mutated
via copy); no behavior impact.
