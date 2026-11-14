# Pi scaffold review — spec v0.3

**Date:** 2026-11-14  
**Verdict:** No actionable scaffold defects found. This is not an SDK acceptance verdict.

## Scope and method

Reviewed `Package.swift`, `README.md`, all files under `Sources/SheepFence/`, both test files, and `Tests/SheepFenceTests/Fixtures/campus-v3.geojson` against `geofence-sdk-spec-v0.3.md`. The specification, manifest, implementation contracts, fixture, and tests were read before the existing `docs/project-review/` reports. Existing reports were then compared with the independent findings.

Review only: no source, manifest, test, fixture, dependency, tool, or environment changes were made.

## Actionable scaffold defects

**None found.** The package declares the expected library and test targets, the fixture resource is packaged, configuration validation matches its documented policy, dataset-scoped region identity is represented, and the public models carry the observation/install metadata required by the proposed contracts. The code and README consistently describe contracts rather than claiming an implemented SDK.

No Critical, Important, or Nit implementation finding met the actionable-defect threshold at this scaffold stage.

## Spec ambiguities and pre-freeze design risks

These are not observed runtime defects; they should be resolved before freezing or implementing the API.

| Severity | Location | Concrete scenario | Suggested fix |
| --- | --- | --- | --- |
| **Medium — spec ambiguity** | `Sources/SheepFence/GeofenceClient.swift:21`; `geofence-sdk-spec-v0.3.md:71` versus `:102` | Section 6 explicitly defines `contains(coordinate:in:) -> Bool`, matching the protocol, while section 3 says region queries carry the adopted revision. If an update commits while a host correlates results, a bare Boolean cannot identify which snapshot answered the query; a separate revision lookup would not atomically bind the two. | Clarify whether section 3 exempts pure Boolean geometry queries. If not, return membership and revision together from the same immutable snapshot; retain a Boolean convenience only with explicit documentation that it is revision-unbound. |
| **Low — design risk, not a demonstrated performance bug** | `Sources/SheepFence/GeofenceClient.swift:15-24` | `@MainActor` covers synchronous `contains` and `evaluate` as well as lifecycle operations. Once section 8.1 requires evaluation across up to 100 regions/10,000 edges, a caller on the main actor could execute all geometry work there and delay UI work. No engine or timing evidence exists yet, and an implementation can offload asynchronous installation internally, so the declaration alone is not proof of a bottleneck. | Revisit isolation with the concrete engine and Release measurements. Keep UI-facing lifecycle state actor-bound if useful, but permit query/evaluation work over immutable snapshots on an appropriate executor if main-actor execution does not meet latency requirements. |

## Explicitly deferred SDK features — not scaffold defects

The README (`README.md:9-13`) expressly declares the package a nonfunctional scaffold. Accordingly, the following absences are planned implementation work, not findings against the current scope:

- **Import and validation (§2):** schema-v1 decoding, strict field validation, polygon/MultiPolygon and ring/hole validation, antimeridian enforcement, and region-ID/JSON-path diagnostics. Public `Codable` value initializers are not import validators.
- **Geometry (§4, §8):** bounding rectangles, point-in-polygon, hole/boundary semantics, MultiPolygon handling, local meter distances, and uncertainty-aware candidate selection.
- **Persistence and revision handling (§3):** concrete Core Data model/store, transactional replacement and rollback, startup restoration, immutable query snapshots, exact-byte retry/SHA-256 conflict behavior, ordered concurrent commits, and zero Core Data reads during queries. `SnapshotStore` and its storage README are contracts only.
- **Observation/event behavior (§3-§4, §6):** confirmed baselines, uncertain observations, entered/exited suppression, deletion/disable cleanup, dataset-change reevaluation without inferred crossings, and location-availability events.
- **Sources and monitoring (§5-§7):** local/bundle/HTTPS acquisition, HTTPS enforcement and download failure behavior, Core Location integration, authorization/service handling, one-source foreground lifecycle, and adaptive sampling. Error cases in `Models.swift` are declarations, not implementations of those behaviors.
- **Release and acceptance decisions (§1, §8–§8.1):** minimum iOS version remains a product decision, as does the location validity window; the explicit configuration parameter addresses the latter without inventing a default. Real-device Release performance, the 100-region workloads, benchmark device, latency, and field accuracy/power thresholds remain unimplemented acceptance work. No functional SDK acceptance is implied by the scaffold tests.

## Tests and verification

Executed in this review session:

```text
$ swift --version
Apple Swift version 6.2.1
Target: arm64-apple-macosx26.0

$ swift test
Build complete! (0.30s)
Test run with 5 tests in 0 suites passed after 0.003 seconds.
Exit status: 0
```

The five Swift Testing test functions cover explicit configuration preservation, nine parameterized nonfinite/out-of-range configuration inputs, dataset-scoped identity, and fixture packaging/basic metadata. XCTest also reported `0 tests` because these tests use Swift Testing; that line is not a test failure.

These tests do **not** demonstrate geometry, import, persistence, monitoring, iOS-device, or section 8/8.1 acceptance. No real-device test was run in this review.
