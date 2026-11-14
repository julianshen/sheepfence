# SheepFence

An iOS polygon geofencing SDK, initialized from
[specification 0.3](geofence-sdk-spec-v0.3.md). Distributed as Swift Package Manager
source with the `SheepFence` library product.

## Status

This is a compiling project scaffold, not a functioning geofence SDK. It includes
public value types, validated configuration, the proposed client/event contract,
an internal persistence contract, and the specification's sample GeoJSON fixture.
There is no concrete client, geometry evaluator, importer, Core Data store,
network downloader, or location provider yet.

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
