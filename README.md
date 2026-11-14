# SheepFence

An iOS polygon geofencing SDK, initialized from
[specification 0.3](geofence-sdk-spec-v0.3.md). Distributed as Swift Package Manager
source with the `SheepFence` library product.

## Status

Implementation is in progress. The package now contains strict GeoJSON import,
polygon/hole/MultiPolygon containment, uncertainty-aware observations, serialized
Core Data persistence, immutable query snapshots, and an internal foreground client
facade. Tests exercise real import/store/engine paths for both 100-region workloads.

It is **not ready for app integration**: the public construction path, production
snapshot downloader, Core Location provider, and adaptive sampling are not wired
up yet. Final cross-review, device lifecycle checks, and field/performance acceptance
remain pending. See [implementation progress](docs/implementation/progress.md).

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
