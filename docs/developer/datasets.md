# Dataset guide

A dataset is a complete GeoJSON snapshot with a stable ID and a monotonically increasing revision. It is separate from the SDK's own release version.

## Minimal snapshot

Save this as `campus.geojson` and include it in your app bundle:

```json
{
  "type": "FeatureCollection",
  "geofenceSchema": 1,
  "dataset": {
    "id": "com.example.campus",
    "revision": 1,
    "generatedAt": "2026-11-14T00:00:00Z"
  },
  "features": [{
    "type": "Feature",
    "id": "campus",
    "properties": { "name": "Campus", "enabled": true, "priority": 0 },
    "geometry": {
      "type": "Polygon",
      "coordinates": [[
        [10.000, 20.000], [10.006, 20.000], [10.006, 20.004],
        [10.000, 20.004], [10.000, 20.000]
      ]]
    }
  }]
}
```

Coordinates are **longitude, latitude**, not the reverse. Rings must be closed and valid. Polygon and MultiPolygon geometries support holes; do not assume arbitrary GeoJSON geometries are accepted. Dataset and feature IDs must be nonempty strings, feature IDs unique within the dataset, revision a positive integer, and `generatedAt` RFC3339 UTC ending in `Z`. Feature `properties` must be an object; omitted `enabled` defaults to true, `priority` to zero, and `name` to the feature ID.

Consult the [full schema and geometry specification](https://github.com/julianshen/sheepfence/blob/main/geofence-sdk-spec-v0.3.md) for topology and boundary rules.

## Install from a file, HTTPS or Data

```swift
let result = try await client.installSnapshot(from: snapshotURL)
print(result.outcome, result.activeRevision)

// If your app handles authenticated networking itself:
let imported = try await client.installSnapshot(data: downloadedData)
```

SDK downloads use HTTPS; redirects are rejected before following them. Standard limits are 5,000,000 bytes and a 30-second transport timeout. Local files and supplied Data are also size-limited. For custom authentication, download in the app and pass Data. Source errors are structured and do not expose URLs or credentials.

## Replacement and revisions

| Input | Result |
|---|---|
| Higher revision | Validate and atomically replace the entire dataset |
| Same revision, identical bytes | `.unchanged` |
| Same revision, different bytes | `revisionConflict` |
| Lower revision | `.olderVersionSkipped` |
| Invalid or failed update | Previous committed dataset remains available |

Unchanged means identical source bytes, not merely equivalent geometry. Do not reformat a published snapshot without incrementing its revision. Omitted features are removed on replacement; this is not a patch API. Different dataset IDs remain independent.

An install that is cancelled before commit begins does not publish the new snapshot. Once durable commit begins, the operation completes and returns its actual outcome even if cancellation arrives. Inspect the result rather than assuming every cancellation means rollback.

## Catalog and removal

```swift
let datasets = await client.datasets()
let regions = try await client.regions(in: "com.example.campus")
let removal = try await client.removeDataset(id: "com.example.campus")
print(removal.wasPresent, removal.removedRegionIDs)
```

Removal is durable and serialized with installs. Removing an absent dataset is a no-op. Removal reports `.datasetRemoved`; it does not generate exits. Reopening a client restores only committed datasets. Location history is not persisted with them.

## Required datasets

Use `expectedDatasetIDs` in configuration when the app requires several datasets before evaluation. Check `state().readiness` for `.noDatasets`, `.missingRequired(...)` or `.ready`. Treat unavailable required data as “not ready,” not as proof that the user is outside.
