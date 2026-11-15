# Changelog

## 1.0.0 — 2026-11-15

First versioned release of SheepFence, a foreground polygon geofencing SDK for
iOS 16+ using Swift 6, distributed as a Swift Package Manager source library.
Licensed under Apache License 2.0.

### SDK

- Polygon/MultiPolygon GeoJSON snapshots with holes and overlapping regions.
- Durable, transactional dataset replacement and removal, revision checks,
  store leases and restoration on open.
- Pure location evaluation, coordinate containment and approximate boundary /
  region distance queries with explicit unsupported-distance results.
- SDK-managed and host-provided foreground monitoring, accuracy-aware
  observations, confirmed entry/exit events and explicit GPS availability.
- Bounded event subscriptions with initial state snapshots, cancellation and
  explicit overflow errors; recovery establishes a new observation baseline.
- Fixed and opt-in adaptive sampling; bounded local/HTTPS snapshot downloads.

### Fence Studio and documentation

- Browser-based polygon drawing/editing, holes, disconnected parts, GeoJSON
  import/export, local drafts and undo/redo.
- Double-click mapped places to import their OSM boundaries.
- Union checked fences while preserving provenance.
- Preview expansion to surrounding road centerlines, with a distance limit,
  Apply/Cancel, hole preservation and undo support.
- English, Traditional Chinese and Japanese developer guides and editor UI.

### Scope and known limitations

- Foreground only. The host app owns permissions and lifecycle. macOS supports
  package/engine testing; macOS location monitoring is not a promised product.
- Distance uses a local approximate model, not walking/driving routes. Inspect
  unsupported results and boundary uncertainty rather than treating them as zero
  distance or outside observations.
- Synthetic tests and recorded device smoke/benchmarks do not establish field
  accuracy, route-crossing timing, energy targets or a performance SLA. Adaptive
  sampling requires application-specific field calibration.
- Fence Studio's tiles and place/road lookup depend on external OSM services and
  map completeness. Live road-provider checks timed out or failed during feature
  verification; road geometry and browser flows were verified with controlled
  fixtures. Failed lookup does not change the dataset. Road alignment follows
  mapped ground-level centerlines, not curbs or legal property boundaries.
- The Swift package has no external dependencies. Bundled editor libraries and
  OSM-derived data retain their separate licenses; see THIRD_PARTY_NOTICES.md.

### Installation

```swift
.package(url: "https://github.com/julianshen/sheepfence", from: "1.0.0")
```

Add `.product(name: "SheepFence", package: "sheepfence")` to the consuming target.
