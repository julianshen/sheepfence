# Know where you are. Understand the uncertainty.

SheepFence is a Swift SDK for foreground polygon geofencing. Bring your own GeoJSON regions, query them offline, and observe confirmed entries and exits without treating missing GPS as “outside.”

**Swift 6 · iOS 16+ · Swift Package Manager · No SDK dependencies**

## Start building

- [Quick start](quick-start.md) — install the package and evaluate your first location.
- [Queries & distance](queries.md) — find matching regions and measure distance to their boundaries.
- [Monitoring & GPS](monitoring.md) — connect a foreground location source and consume events.
- [Dataset guide](datasets.md) — author, install, replace and remove GeoJSON snapshots.
- [API guide](api.md) — choose the right method and configure the client.
- [Troubleshooting](troubleshooting.md) — diagnose availability, imports and slow consumers.
- [Contributing](contributing.md) — build, test and maintain the documentation.

## Choose the right operation

| What your app needs | API |
|---|---|
| Which regions contain this GPS fix? | `evaluate(location:)` |
| Is this coordinate inside a specific region? | `query(coordinate:in:)` |
| How far is this coordinate from a region? | `distance(from:to:)` |
| Track transitions using your own GPS provider | `startMonitoring(mode: .hostProvided)` then `submit(location:)` |
| Track transitions using the SDK's provider | `startMonitoring(mode: .sdkManaged)` |
| Read current monitoring status | `state()` |
| Receive state, evaluations and crossings | `events()` |

## Designed for explicit answers

Multiple overlapping regions can match the same fix. Observations distinguish confirmed membership, boundary uncertainty and unavailable location. Dataset revision metadata identifies the geometry behind a result. Missing location preserves the last confirmation as history; it does not invent an exit.

Snapshot updates are transactional. A rejected update leaves the committed dataset usable, and a geometry replacement establishes a new baseline instead of manufacturing movement events.

## Current status

The SDK is available from the repository's `main` branch; no versioned release is published. The implementation was independently reviewed by Codex, OpenCode and pi. The recorded checkpoint passed 139 tests in 25 suites, simulator tests, and an iPhone smoke check with a 100-area synthetic benchmark. These are checkpoint results, not a performance guarantee.

Foreground use is the supported integration model. Real-route accuracy, energy calibration and permission-state field acceptance remain separate work. Licensing must be selected before a versioned distribution.

[View validation evidence](https://github.com/julianshen/sheepfence/blob/main/docs/implementation/sdk-progress.md) · [Browse the source](https://github.com/julianshen/sheepfence)
