# API guide

`SheepFenceClient` is the main-actor concrete facade. `GeofenceClient` is the public Sendable protocol for dependency injection and application mocks. Public result payloads provide initializers.

## Client operations

| Operation | Result | Changes monitoring state? |
|---|---|---|
| `SheepFenceClient.open(storeURL:configuration:)` | Restored client | Creates a new stopped session |
| `installSnapshot(from:)` / `installSnapshot(data:)` | `InstallResult` | May rebase observations after a dataset update |
| `datasets()` | `[DatasetSummary]` | No |
| `regions(in:)` / `regions()` | `[RegionSummary]` | No |
| `removeDataset(id:)` | `DatasetRemovalResult` | Removes dataset observations |
| `query(coordinate:in:)` | `GeometryQueryResult` | No |
| `contains(coordinate:in:)` | `Bool` | No |
| `distance(from:to:)` | `RegionDistanceResult` | No |
| `evaluate(location:)` | `EvaluationBatch` | No |
| `submit(location:)` | `EvaluationBatch` | Yes; active host-provided mode only |
| `state()` | `MonitoringState` | No; projects current freshness |
| `events(bufferCapacity:)` / `events()` | Throwing async event stream | Adds a subscriber |
| `startMonitoring(mode:)` | `Void` | Yes |
| `stopMonitoring()` | `Void` | Yes |
| `updateAvailability(_:)` | `Void` | Yes; host availability input |

All client operations are asynchronous. `datasets`, `state` and `stopMonitoring` do not throw; the others above can throw. `evaluate` and `submit` accept both `LocationSample` and `CLLocation`. See the [protocol source](https://github.com/julianshen/sheepfence/blob/main/Sources/SheepFence/GeofenceClient.swift) for exact declarations and the [DocC overview](https://github.com/julianshen/sheepfence/blob/main/Sources/SheepFence/SheepFence.docc/SheepFence.md) for symbol-oriented documentation.

## Configuration

```swift
let configuration = try GeofenceConfiguration(
    maximumLocationAge: 30,
    boundaryBufferMeters: 5,
    maximumFutureSkew: 1,
    expectedDatasetIDs: ["com.example.campus"],
    downloadPolicy: DownloadPolicy(maximumBytes: 5_000_000, timeout: 30),
    sampling: .fixed(LocationSamplingConfiguration(
        distanceFilterMeters: 10,
        desiredAccuracyMeters: 10
    ))
)
```

These numbers illustrate configuration; they are not field-calibrated recommendations. The outer `try` covers the nested throwing initializers.

| Setting | Default / constraint |
|---|---|
| `maximumLocationAge` | Required; finite, greater than zero seconds |
| `boundaryBufferMeters` | 0; finite, nonnegative |
| `maximumFutureSkew` | 0; finite, nonnegative seconds |
| `expectedDatasetIDs` | Empty set; IDs must be nonempty |
| `downloadPolicy` | `.standard`: 5,000,000 bytes / 30 seconds |
| `sampling` | `.fixed(.standard)`: 10 m filter / 10 m accuracy |

Fixed desired accuracy must be finite and positive. The distance filter must be finite and nonnegative; zero disables the filter. Negative Core Location accuracy sentinels are intentionally not accepted by this meters-based configuration API.

## Key result types

- `EvaluationBatch`: evaluation time, sample time, dataset metadata and region results.
- `RegionEvaluation`: identity, revision, observation time, observation and optional historical confirmation.
- `MonitoringState`: active mode, readiness, availability, installed datasets and current evaluations.
- `RegionDistanceResult`: membership, revision, supported/unsupported boundary estimate and optional distances.
- `DatasetChange`: dataset metadata, affected/removed IDs and available rebased evaluations.

Read [queries](queries.md), [monitoring](monitoring.md) and [datasets](datasets.md) for behavior, rather than inferring it from type names alone.

## Migrating an early integration

The old stateful `evaluate` is now split into pure `evaluate` and stateful `submit`. Simply adding `.results` to an old call does not preserve its behavior. Events now throw and include an initial state snapshot and evaluated batches. The old four-argument factory is deprecated; put download and sampling policies in configuration.

Follow the [migration guide](https://github.com/julianshen/sheepfence/blob/main/docs/sdk-migration.md) when upgrading an existing host.
