# SheepFence

An iOS polygon geofencing SDK, initialized from
[specification 0.3](geofence-sdk-spec-v0.3.md). Distributed as Swift Package Manager
source with the `SheepFence` library product.

## Status

Implementation is in progress. The package now contains strict GeoJSON import,
polygon/hole/MultiPolygon containment, uncertainty-aware observations, serialized
Core Data persistence, immutable query snapshots, and a public foreground client
facade. Tests exercise real import/store/engine paths for both 100-region workloads.

The public construction path restores SQLite snapshots and connects the local/HTTPS
source, Core Location provider, and adaptive sampling. Source/provider cross-review
and regression fixes are complete for this checkpoint (86 package tests pass). Device lifecycle checks and field/performance
acceptance remain pending; this is not a release-ready SDK.
See [implementation progress](docs/implementation/progress.md).

Distance evaluation uses an approximate local meter model, currently limited to
query latitudes within 80 degrees and vertices within one degree of the query.
Outside this support envelope it returns uncertainty rather than claiming a precise
boundary separation. Pure coordinate containment preserves GeoJSON straight edges;
the dataset itself is not rejected for exceeding the meter-model envelope.

## Development

Open `Package.swift` in Xcode, or run with a Swift 6 toolchain on macOS:

```sh
swift build
swift test
```

The package provisionally targets iOS 16+. macOS 13+ supports local package tests;
it is not a promise of a macOS monitoring product. Confirm the minimum iOS version
before release. No third-party dependencies are required by this scaffold.

The host owns foreground lifecycle and Core Location permission prompts, including
`NSLocationWhenInUseUsageDescription`. `GeofenceConfiguration` requires an explicit
location validity window; the specification does not yet prescribe one.

## Opening a client

Call from the main actor with a writable SQLite file URL in an existing directory:

```swift
let client = try await SheepFenceClient.open(
    storeURL: storeURL,
    configuration: GeofenceConfiguration(maximumLocationAge: 60),
    downloadPolicy: DownloadPolicy(maximumBytes: 5_000_000, timeout: 30),
    samplingConfiguration: SamplingPolicyConfiguration()
)
let events = await client.events()
let eventTask = Task {
    for await event in events {
        // Handle baseline, movement, dataset and availability events.
    }
}
try await client.installSnapshot(from: bundledGeoJSONURL)
try await client.startMonitoring(mode: .sdkManaged)
// When the host leaves the foreground:
await client.stopMonitoring()
eventTask.cancel()
```

The values above illustrate configuration, not measured product thresholds.
The host requests location authorization separately. Use `.hostProvided` when
the app owns location acquisition, then call `evaluate(location:)` and
`updateAvailability(_:)`; do not mix both sources in one active session.
Coordinate-only `query(coordinate:in:)` works offline after restoration and does
not emit movement events. Retain the client for the session and explicitly stop
monitoring when the host leaves the foreground.

## Implementation sequence

1. Decode and validate schema v1, properties, rings, holes and MultiPolygons, with
   feature IDs and JSON paths in errors. Enforce antimeridian splitting.
2. Implement bounding-box filtering, polygon containment (including hole boundaries),
   and local meter distances with uncertainty-aware candidate selection.
3. Implement transactional Core Data persistence, revision rules, SHA-256 identity,
   startup restoration and immutable query snapshots.
4. Implement observation baselines, uncertainty handling, transitions, dataset-change
   reevaluation and asynchronous events.
5. Implement local/HTTPS installation and foreground Core Location integration,
   with a single location source per session and adaptive sampling.
6. Run all section 8 acceptance cases and section 8.1 capacity workloads through
   the production importer and store. Measure Release P50/P95 on a real iPhone.

Before acceptance, select a benchmark device, maximum location age, acceptable
event latency, and field-tested accuracy/power thresholds. SDK Git release tags
(for example `0.1.0`) are independent of `dataset.revision`.
