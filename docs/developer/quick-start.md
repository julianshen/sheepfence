# Quick start

Open a persistent client, install a snapshot and evaluate a location. One-shot queries do not start a GPS provider or modify monitoring history.

## 1. Add the Swift package

In Xcode, choose **File → Add Package Dependencies**, enter `https://github.com/julianshen/sheepfence`, choose **Up to Next Major Version**, starting at **1.0.0**, and add the `SheepFence` product to your app target. For a Swift package:

```swift
.package(url: "https://github.com/julianshen/sheepfence", from: "1.0.0")
```

Add `.product(name: "SheepFence", package: "sheepfence")` to the target's dependencies. Requires Swift 6 and iOS 16+. macOS 13+ supports package/engine testing; macOS location monitoring is not a promised product surface. Commit your app’s `Package.resolved` for reproducible dependency resolution.

## 2. Open and retain one client

This complete helper opens an Application Support store and imports a bundled snapshot. Add a valid `campus.geojson` to your app target; the [dataset guide](datasets.md) includes a sample.

```swift
import Foundation
import SheepFence

@MainActor
func openGeofences(snapshotURL: URL) async throws -> SheepFenceClient {
    let support = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    let storeURL = support.appendingPathComponent("SheepFence/regions.sqlite")
    let configuration = try GeofenceConfiguration(maximumLocationAge: 60)
    let client = try await SheepFenceClient.open(
        storeURL: storeURL,
        configuration: configuration
    )
    _ = try await client.installSnapshot(from: snapshotURL)
    return client
}
```

Retain the returned client in a main-actor application model. Opening restores committed datasets and creates missing parent directories. Only one live client may own a canonical store path within a process. Reuse it across views; stop monitoring when the app leaves the foreground.

The 60-second validity window is an example product choice. Set it to match your app's requirements. Opening a client never prompts for location permission.

## 3. Evaluate a fix

Given a retained `client` and a `CLLocation` supplied by your app:

```swift
let batch = try await client.evaluate(location: currentLocation)
let matches = batch.results.filter {
    $0.observation == .confirmed(.inside)
}
for match in matches {
    print(match.regionID.datasetID, match.regionID.featureID)
}
```

The result may contain several matches. Handle `.boundaryUncertain` and `.unavailable` explicitly rather than displaying them as outside. For a reproducible manual sample inside the guide's campus polygon:

```swift
let sample = LocationSample(
    coordinate: Coordinate(longitude: 10.003, latitude: 20.002),
    timestamp: Date(),
    horizontalAccuracy: 5
)
let batch = try await client.evaluate(location: sample)
```

The manual sample is for integration checks, not a replacement for live device location.

## 4. Add monitoring when needed

Use [monitoring & GPS](monitoring.md) when you need ongoing evaluations or entry/exit events. `evaluate` is pure; calling it repeatedly will never generate crossings. Use `submit` in host-provided mode, or let SDK-managed mode receive GPS fixes.

A runnable iOS host is available in [Examples/ForegroundHost](https://github.com/julianshen/sheepfence/tree/main/Examples/ForegroundHost). Its README covers simulator, device and benchmark setup.
