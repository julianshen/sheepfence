# SheepFence

A foreground polygon geofencing SDK for iOS, distributed as a Swift Package Manager
source library. Supports GeoJSON Polygon/MultiPolygon regions, overlapping areas,
offline snapshots, accuracy-aware observations and confirmed entry/exit events.

[Developer documentation](https://julianshen.github.io/sheepfence/) · [Quick start](docs/developer/quick-start.md) · [API guide](docs/developer/api.md)

[繁體中文文件](https://julianshen.github.io/sheepfence/zh-Hant/) · [日本語ドキュメント](https://julianshen.github.io/sheepfence/ja/)

## Create fence polygons

[Open Fence Studio](https://julianshen.github.io/sheepfence/editor.html) to double-click mapped places for their boundaries, draw and edit polygons on OpenStreetMap, and export SDK-ready GeoJSON. Includes holes, MultiPolygon parts, import, local drafts and undo/redo. [Editor guide](docs/developer/fence-editor.md).

## Install

Add `https://github.com/julianshen/sheepfence` in Xcode's package dependencies and
select the `SheepFence` product. Development currently uses the `main` branch; there
is no versioned release tag yet.
Requires Swift 6 and iOS 16+. macOS 13+ is supported for package/engine testing, not
as a promised macOS location-monitoring product. No third-party dependencies.

## Open a client

Call from the main actor. Opening creates missing parent directories and restores
committed datasets. Keep one live client per canonical SQLite URL.

```swift
import SheepFence

let client = try await SheepFenceClient.open(
    storeURL: storeURL,
    configuration: GeofenceConfiguration(maximumLocationAge: 60)
)
try await client.installSnapshot(from: bundledGeoJSONURL)
```

`maximumLocationAge` is your product choice; 60 seconds is an example. Input may be
a bundle/local file, HTTPS URL, or `Data` via `installSnapshot(data:)`. Apps with
custom authentication download their own data. Remote redirects are rejected;
default limits are 5,000,000 bytes and 30 seconds. Replace them with `DownloadPolicy`
in configuration when needed.

Datasets use full-snapshot replacement and monotonic revisions. Failed imports keep
the previous data available. List metadata with `datasets()` / `regions(in:)`, and
remove data with `removeDataset(id:)`. See the [GeoJSON specification](geofence-sdk-spec-v0.3.md).

## Where am I?

```swift
let batch = try await client.evaluate(location: currentLocation) // CLLocation or LocationSample
let inside = batch.results.filter { $0.observation == .confirmed(.inside) }
```

This evaluates all enabled regions without changing tracking state or emitting events.
Several overlapping regions may match. `boundaryUncertain` means the reported GPS
accuracy cannot support a confirmed answer. An unavailable observation is not outside.

For coordinate-only geometry, use `query(coordinate:in:)` or `contains(coordinate:in:)`.
Named disabled regions can also be queried. Results identify the dataset revision used.

## How far to a region?

```swift
let distance = try await client.distance(from: coordinate, to: regionID)
let toRegion = distance.distanceToRegionMeters       // 0 inside; nearest edge outside
let toEdge = distance.distanceToBoundaryMeters       // nearest edge from either side
```

Inspect `boundaryDistance` for `.approximateMeters` versus `.unsupported`. Unsupported
outside distances return nil, never a fabricated zero. This is straight-line distance,
not walking/driving distance, and does not account for GPS accuracy.

The current local meter model supports query latitudes within 80 degrees and every
geometry vertex within one degree of the query in latitude/unwrapped longitude.
A distant component makes distance unsupported. Coordinate containment still works;
monitoring remains conservative about uncertain boundary separation.

## Foreground monitoring

The app owns permission prompts, `NSLocationWhenInUseUsageDescription` and foreground
lifecycle. The SDK never requests permission automatically.

```swift
let stream = try await client.events()
let eventTask = Task { @MainActor in
    do {
        for try await event in stream {
            // Handle initial/current state, evaluated batches, crossings and diagnostics.
            handle(event)
        }
    } catch {
        // Includes slow-consumer overflow. Resubscribe to recover current state.
        showError(error)
    }
}
try await client.startMonitoring(mode: .sdkManaged)

// When leaving foreground:
await client.stopMonitoring()
// When disposing the subscriber:
eventTask.cancel()
```

For app-owned GPS, start `.hostProvided`, call `submit(location:)`, and report source
availability with `updateAvailability(_:)`. `submit` changes monitoring state;
`evaluate` remains a pure query in any mode. Stop before switching modes.

Use `state()` for an atomic current-state snapshot. GPS loss reports unavailable and
retains historical last confirmation with its timestamp. Recovery establishes a baseline
instead of inferring a crossing through the outage. No expiry timer event is promised;
refresh state or use timestamps when rendering potentially stale observations.

Each subscription has an independent ordered buffer (default 256). Overflow terminates
that subscriber with an explicit error; it does not silently drop crossings or block GPS
processing. Initial state is delivered atomically before later events. Streams are not
durable movement logs. No location history is persisted or uploaded.

Fixed sampling defaults to requested 10 m accuracy / 10 m distance filter. These are
Core Location requests, not guarantees. Adaptive sampling is explicitly opt-in via
`SamplingMode.adaptive` and requires field calibration.

## Documentation and validation

- [Developer guides](docs/developer/index.md) — installation, queries, monitoring, datasets and troubleshooting
- [Documentation website](https://julianshen.github.io/sheepfence/)
- [DocC overview](Sources/SheepFence/SheepFence.docc/SheepFence.md)
- [Migration guide](docs/sdk-migration.md) — the earlier stateful evaluate API changes
- [Foreground example app](Examples/ForegroundHost/README.md)
- [SDK completion evidence](docs/implementation/sdk-progress.md)
- [Acceptance coverage](docs/implementation/acceptance.md)

```sh
swift build
swift test
```

The SDK has deterministic tests for storage, geometry, public integration, availability,
events, cancellation and capacity. Physical GPS/lifecycle and field accuracy/energy
acceptance remain separate from synthetic tests; this is pre-release software. There
is no performance SLA or background-monitoring guarantee. Release version and licensing
remain to be selected before a versioned distribution.
