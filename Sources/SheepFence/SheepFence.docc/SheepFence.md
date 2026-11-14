# ``SheepFence``

Evaluate polygon regions offline and observe foreground geofence transitions.

## Overview

SheepFence is a Swift Package Manager library for iOS 16 and later using Swift 6.
It accepts validated GeoJSON Polygon and MultiPolygon datasets, persists committed
snapshots, and evaluates enabled regions without querying the store for every location.
Multiple overlapping regions can match one location.

The app owns location permission prompts and foreground lifecycle. This SDK does
not request permission, monitor in the background, upload locations, or persist
movement history. macOS support is intended for local engine and package testing.

## Open and install

Create one client per store URL. `open` creates parent directories and restores
committed snapshots before returning. A corrupt store throws instead of being deleted.
Do not share a SQLite file between app processes or extensions.

```swift
let client = try await SheepFenceClient.open(
    storeURL: storeURL,
    configuration: GeofenceConfiguration(maximumLocationAge: 60)
)
let installed = try await client.installSnapshot(from: bundledFileURL)
```

Local files, bundle files and HTTPS URLs are accepted. Use `installSnapshot(data:)`
for an authenticated download performed by your app. The same configured byte limit
applies to every input. Remote redirects are rejected. A newer dataset replaces the
whole previous revision atomically. An identical resend is unchanged; an older revision
is skipped; equal revision with different bytes is a conflict. A failed import leaves
the prior committed dataset usable.

`datasets()` and `regions(in:)` provide display metadata, including disabled regions.
`removeDataset(id:)` deletes a dataset and its observation history without exit events.
Removing a missing dataset is an idempotent no-op. Pending installs are not cancelled
by removal and may recreate the dataset if they commit later.

## Find the regions containing a location

```swift
let batch = try await client.evaluate(location: location)
let inside = batch.results.filter { $0.observation == .confirmed(.inside) }
```

`location` may be a `CLLocation` or a `LocationSample`. This is a pure one-shot query:
it does not start GPS, change monitoring baselines, or emit events. It checks sample
freshness, accuracy and boundary uncertainty independently of SDK provider availability.
An unavailable observation never means outside. Near a boundary, an observation may
be uncertain even when coordinate-only geometry says inside.

`contains(coordinate:in:)` and `query(coordinate:in:)` answer geometry-only membership
for a named region, including disabled regions. `query` includes the revision used.
They do not account for GPS accuracy or freshness.

## Distance

```swift
let result = try await client.distance(from: coordinate, to: regionID)
switch result.boundaryDistance {
case .approximateMeters(let meters):
    print("Nearest edge: \(meters) meters")
case .unsupported(let reason):
    print("Distance unavailable: \(reason)")
}
```

`distanceToRegionMeters` is zero inside and nearest-edge distance outside.
`distanceToBoundaryMeters` is nearest-edge distance from either side. Unsupported
boundary estimates produce nil convenience values, except distance to the region
is still zero when containment proves the coordinate inside.

This is approximate straight-line distance, not walking/driving distance. It ignores
GPS accuracy and timestamp. Hole edges are boundaries; points inside a hole are outside
the region. All MultiPolygon components participate. The local approximation supports
query latitudes within 80 degrees and every geometry vertex within one degree of the
query in latitude and unwrapped longitude. A distant component makes the distance
unsupported. Never substitute zero for an unsupported outside distance.

## Foreground monitoring

Subscribe before starting:

```swift
let stream = try await client.events()
let task = Task { @MainActor in
    do {
        for try await event in stream {
            switch event {
            case .evaluated(let batch):
                render(batch.results)
            case .stateSnapshot(let state):
                renderState(state)
            default:
                handleTransitionOrDiagnostic(event)
            }
        }
    } catch {
        // Resubscribe to obtain current state; missed transitions are not replayed.
        showError(error)
    }
}
try await client.startMonitoring(mode: .sdkManaged)
```

Your app must request When In Use permission and supply its usage description. Start
only when foreground active; call `stopMonitoring()` when leaving foreground. A stop
completes cleanup even if the caller is cancelled. Repeated start in the same mode and
repeated stop are idempotent. Stop before switching modes. An empty enabled-region
set does not start the provider; later installs can activate it.

For app-owned locations, start `.hostProvided` and call `submit(location:)`. This
updates monitoring state and may emit baseline, entered or exited events. Use
`updateAvailability(_:)` to report loss/recovery of your source. Both calls require
active host-provided mode. Do not mix host submissions with SDK-managed GPS.

## GPS loss and current state

`state()` returns an atomic snapshot of readiness, availability, datasets and current
observations. When GPS is unavailable, show that reason; a historical `lastConfirmed`
state and timestamp are not a claim about current position. Reduced accuracy is a
separate flag; samples still use their reported horizontal accuracy.

Availability loss or a prolonged sample gap resets transition baselines. The first
confirmable recovery observation is a baseline, not a crossing inferred across the gap.
Stale observations are projected as unavailable when reading state or subscribing.
There is no expiry timer event: use timestamps or refresh state when rendering/resuming.

## Event delivery

Every subscriber receives an initial state snapshot registered atomically before later
events. The stream is independent, ordered and bounded (default capacity 256). Every
stateful evaluation batch is reported after any transitions from that input. An
unconsumed full buffer terminates that subscriber with `eventBufferOverflow`; other
subscribers and location processing continue. Resubscription recovers current state,
not past transitions. Cancel the consuming task when its owner is disposed.

## Configuration and failures

Choose `maximumLocationAge` explicitly; examples are not field-calibrated recommendations.
Fixed sampling requests 10 m desired accuracy and 10 m distance filter by default;
these are requests to Core Location, not guarantees. Adaptive sampling is opt-in and
requires product field validation. Downloads default to a 5,000,000-byte limit and
30-second timeout; override with `DownloadPolicy`.

Public operations throw structured `GeofenceError` or `CancellationError`. Handle
readiness, revision conflicts, invalid snapshots and source failures separately from
location availability. Cancellation before a queued commit starts prevents the update;
once commit starts it finishes and reports the actual outcome. Source errors do not
include credentials, response bodies or raw network error descriptions.
