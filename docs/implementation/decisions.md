# Implementation decisions — contract baseline

The user authorized implementation of reviewed plan revision 3. Existing tabs share one implementation branch with disjoint file ownership; no additional agents or workspaces are created. Codex serializes shared-file edits and commits.

- `query` returns binary geometry membership and revision atomically; `contains` is explicitly a Bool convenience exception to spec section 3. Location evaluation separately handles uncertainty.
- Public async client delegates to an engine actor; MainActor is reserved for the provider/facade. Immutable Sendable value snapshots never expose Core Data objects.
- Source mode is explicit. Starting the same mode is idempotent; changing mode while active throws. Host-provided single-shot evaluation works without starting tracking; SDK-managed sessions reject host submissions. Availability changes have a host API, with reduced accuracy represented separately from unavailability.
- The caller chooses maximum location age. Future skew defaults to zero (strict); callers may configure a nonnegative allowance. Nonfinite timestamps/accuracy are unavailable. Samples older than the latest accepted sample do not change state; equal timestamps are duplicates and do not create crossings. An interruption resets the ordering watermark and recent sample.
- `expectedDatasetIDs` permits explicit readiness expectations. No installed datasets is not-ready. An installed empty dataset is ready; querying a missing feature returns region-not-found.
- Event streams are independent multicast subscriptions with unbounded FIFO buffering to avoid silent dropped crossings. Consumers must cancel unused subscriptions. Termination unregisters subscribers. Dataset changes carry affected/removed IDs and rebased evaluations; no data-driven standalone crossing/baseline events.
- Redirects are rejected, credentials/cookies are not ambient, byte and timeout limits are explicit required DownloadPolicy inputs. No partial download reaches the importer.
- Sort by descending priority, feature ID, then dataset ID.
- Geometry uses coordinate-linear edges, ring positions define roles, either winding is accepted. Touching holes/shells and touching/overlapping holes are rejected for unambiguous simple topology. Consecutive duplicate vertices may be rejected with a path. Unsplit edges with longitude delta >180 are rejected; split antimeridian components are supported. No arbitrary global extent rejection is added; meter estimates use a documented local projection and far/global queries must remain conservative (uncertain or exact fallback rather than false certainty). Numeric tolerance and local-projection approximation evidence are part of geometry review, not an unmeasured accuracy promise.
- iOS 16/Swift 6 is the provisional engineering target. Device, latency/accuracy/power thresholds and representative-site access remain release gates, not inferred values.

## Fixed worker interfaces

OpenCode implements `GeoJSONDecoder.decode(_ data: Data) throws -> ValidatedSnapshot` (static), and `Geometry.contains(_ point: Coordinate, in geometry: RegionGeometry) -> Bool`, `Geometry.distanceToBoundary(_ point: Coordinate, in geometry: RegionGeometry) -> Double` (meters, static). Engine may initially compute distance for every enabled region; safe pruning is an optimization only after counterexamples pass.

Pi implements `CoreDataSnapshotStore` conforming to SnapshotStore, with `init(url: URL) throws` for SQLite durability and an explicit in-memory testing option. `commit` returns SnapshotCommit containing the actual effective snapshot. Implement `HTTPSnapshotSource(policy:)` conforming to SnapshotSource for local and HTTPS reads. Provider implements the existing MainActor LocationProvider protocol. Send proposed API additions to Codex before editing shared types.
