# Queries & distance

Use queries for answers about a supplied coordinate or GPS fix. They do not change monitoring state or emit events, and they work independently of the active monitoring mode.

## Which region am I in?

```swift
let batch = try await client.evaluate(location: currentLocation)
for result in batch.results {
    switch result.observation {
    case .confirmed(.inside):
        print("Inside", result.regionID)
    case .confirmed(.outside):
        print("Outside", result.regionID)
    case .boundaryUncertain:
        print("Too close to the boundary for a confirmed answer")
    case .unavailable(let reason):
        print("Location unavailable:", reason)
    }
}
```

`evaluate` accepts `CLLocation` or `LocationSample`. It considers enabled regions and checks sample validity, age and horizontal accuracy. Inspect `batch.datasets` and each result's `revision` for snapshot attribution. One-shot results have no monitoring `lastConfirmed` history.

A stale, future-dated or invalid fix cannot confirm membership. A large accuracy radius can overlap the boundary even when the reported coordinate is geometrically inside. An empty list is not proof that you are outside every region: inspect the catalog and dataset readiness too.

## Coordinate-only containment

```swift
let region = RegionID(datasetID: "com.example.campus", featureID: "campus")
let coordinate = Coordinate(longitude: 10.003, latitude: 20.002)
let result = try await client.query(coordinate: coordinate, in: region)
let inside = try await client.contains(coordinate: coordinate, in: region)
```

`query` returns membership and revision metadata. `contains` is a Boolean convenience. These calls intentionally ignore GPS accuracy and age; they answer a geometry question, not a confirmed-location question. Explicitly named disabled regions can also be queried. Region identity is the dataset ID plus feature ID, not the display name.

## Distance to a region or its boundary

```swift
let result = try await client.distance(from: coordinate, to: region)
let toRegion: Double? = result.distanceToRegionMeters
let toBoundary: Double? = result.distanceToBoundaryMeters

switch result.boundaryDistance {
case .approximateMeters(let meters):
    print("Nearest boundary:", meters, "m")
case .unsupported(let reason):
    print("No supported boundary estimate:", reason)
}
```

| Position / support | Distance to region | Distance to boundary |
|---|---|---|
| Inside, estimate supported | `0` | Approximate nearest edge distance |
| Outside, estimate supported | Approximate nearest edge distance | Same value |
| Inside, estimate unsupported | `0` | `nil` |
| Outside, estimate unsupported | `nil` | `nil` |

A supported zero is different from an unsupported estimate. Never replace an absent outside distance with zero in your UI. Results use a single committed snapshot and include its revision.

Distances are approximate straight-line meters, not route distances. They do not include the fix's accuracy radius. The local model requires query latitude within ±80° and every geometry vertex within one degree of the query in latitude and unwrapped longitude. A distant MultiPolygon component can make the estimate unsupported even when another component is nearby. Containment still works outside this distance model.

## Choosing between evaluate and submit

Use `evaluate` for search, previews and “check this point” actions. Use `submit` only for actual monitoring input after starting `.hostProvided`. Submitting affects history and can generate baseline or crossing events; it enforces sample ordering as part of that stateful session.
