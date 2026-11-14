import CoreLocation
import Foundation

public struct DatasetChange: Equatable, Sendable {
    public let dataset: DatasetMetadata
    public let affectedRegionIDs: [RegionID]
    public let removedRegionIDs: [RegionID]
    /// Empty when no current sample exists. affectedRegionIDs still identifies unconfirmed regions.
    public let evaluations: [RegionEvaluation]
    public init(dataset: DatasetMetadata, affectedRegionIDs: [RegionID], removedRegionIDs: [RegionID], evaluations: [RegionEvaluation]) {
        self.dataset = dataset; self.affectedRegionIDs = affectedRegionIDs
        self.removedRegionIDs = removedRegionIDs; self.evaluations = evaluations
    }
}
public enum GeofenceEvent: Equatable, Sendable {
    case stateSnapshot(MonitoringState)
    case evaluated(EvaluationBatch)
    case datasetRemoved(DatasetRemovalResult)
    /// Background provider evaluation errors, distinct from import errors thrown by install.
    case evaluationFailed(GeofenceError)
    case baseline(RegionEvaluation)
    case entered(RegionEvaluation)
    case exited(RegionEvaluation)
    case datasetChanged(DatasetChange)
    case locationAvailabilityChanged(LocationAvailability)
}

/// Foreground SDK interface. The host owns permissions and scene lifecycle.
/// Each bounded subscription starts with an atomic current-state snapshot.
public protocol GeofenceClient: Sendable {
    func events(bufferCapacity: Int) async throws -> AsyncThrowingStream<GeofenceEvent, Error>
    func installSnapshot(from source: URL) async throws -> InstallResult
    func installSnapshot(data: Data) async throws -> InstallResult
    func datasets() async -> [DatasetSummary]
    func regions(in datasetID: String?) async throws -> [RegionSummary]
    func removeDataset(id: String) async throws -> DatasetRemovalResult
    func query(coordinate: Coordinate, in region: RegionID) async throws -> GeometryQueryResult
    func distance(from coordinate: Coordinate, to region: RegionID) async throws -> RegionDistanceResult
    func evaluate(location: LocationSample) async throws -> EvaluationBatch
    func submit(location: LocationSample) async throws -> EvaluationBatch
    func state() async -> MonitoringState
    func startMonitoring(mode: LocationSourceMode) async throws
    func stopMonitoring() async
    func updateAvailability(_ availability: LocationAvailability) async throws
}
public extension GeofenceClient {
    func events() async throws -> AsyncThrowingStream<GeofenceEvent, Error> { try await events(bufferCapacity: 256) }
    func regions() async throws -> [RegionSummary] { try await regions(in: nil) }

    /// Convenience without revision metadata. Use query for snapshot attribution.
    func contains(coordinate: Coordinate, in region: RegionID) async throws -> Bool {
        try await query(coordinate: coordinate, in: region).membership == .inside
    }
    func evaluate(location: CLLocation) async throws -> EvaluationBatch {
        try await evaluate(location: LocationSample(location))
    }
    func submit(location: CLLocation) async throws -> EvaluationBatch {
        try await submit(location: LocationSample(location))
    }
}
public extension LocationSample {
    init(_ location: CLLocation) {
        self.init(coordinate: Coordinate(longitude: location.coordinate.longitude, latitude: location.coordinate.latitude),
                  timestamp: location.timestamp, horizontalAccuracy: location.horizontalAccuracy,
                  speed: location.speed.isFinite && location.speed >= 0 ? location.speed : nil)
    }
}
