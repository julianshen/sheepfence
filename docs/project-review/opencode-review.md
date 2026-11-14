# OpenCode scaffold review — spec v0.3

**Scope:** `Package.swift`, `Sources/SheepFence/*`, `Tests/SheepFenceTests/*` (including fixture), and README/storage notes reviewed against `geofence-sdk-spec-v0.3.md`. Existing `docs/project-review/*` reports were read only after independent source/spec review. No source changes, subagents, or environment updates were made.

## Actionable scaffold defects

**None found.** The scaffold compiles as a contract/value-type package: manifest/targets/resources are coherent, public models expose required identity/result/observation fields, configuration rejects the specified invalid inputs, and tests cover the implemented validation and fixture packaging.

## Explicitly deferred (not scaffold defects)

- Concrete `GeofenceClient` engine, event emission/baselines/reevaluation, and monitoring lifecycle behavior (§4, §6).
- GeoJSON schema-v1 import/validation, geometry/ring/hole/antimeridian handling, bbox/PIP/distance evaluation, and revision/error reporting by region/path (§2–§4).
- Core Data `SnapshotStore` implementation, transactional commit/rollback, startup restore, immutable in-memory query snapshots, SHA-256 conflict handling, and zero-query-read acceptance (§3, `Sources/SheepFence/Storage/README.md`).
- Local/bundle/HTTPS snapshot acquisition and network security enforcement details (`GeofenceError.unsupportedSource`/`downloadFailed` are declarations only) (§3, §6).
- Foreground/Core Location integration, permission/accuracy handling, adaptive sampling, and all §8/§8.1 functional/performance acceptance on real devices (§5, §7, §8).

## Spec ambiguities / design risks to resolve before API freeze

| Severity | Location | Scenario | Suggested fix |
| --- | --- | --- | --- |
| Medium (ambiguity) | `Sources/SheepFence/GeofenceClient.swift:21`, spec §3 (`geofence-sdk-spec-v0.3.md:71`) vs §6 (`:102`) | §6 defines `contains(coordinate:in:) -> Bool`, but §3 states “區域查詢與事件均帶上採用的 revision”. A caller cannot tell which committed snapshot answered a pure-geometry query, so results cannot be reliably correlated with `datasetChanged`/evaluation revisions under concurrent updates. | Clarify spec: either explicitly exempt pure Boolean geometry queries from revision tagging, or change API to return membership + revision (and keep a Bool convenience only if it is explicitly snapshot-unbound/documented). |
| Low (design risk) | `Sources/SheepFence/GeofenceClient.swift:15-24` | The entire client contract, including synchronous `contains`/`evaluate`, is `@MainActor`. With future in-memory geometry over many regions/edges this may force query work onto the UI actor or require awkward hopping; no engine/timing evidence exists in this scaffold. | Revisit isolation when implementing: keep UI-facing state/event delivery actor-bound if needed, but allow query/evaluation work on an appropriate executor over immutable snapshots, consistent with spec concurrency intent. |

## Verification

Not executed in this review session; assessment is source/spec based. (Per README: `swift build` / `swift test` are the local checks; prior repo review notes recorded passing local build/test, but not real-device acceptance.)
