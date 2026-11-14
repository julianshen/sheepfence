import CoreLocation
import Foundation

public struct DatasetChange: Equatable, Sendable {
    public let dataset: DatasetMetadata
    public let affectedRegionIDs: [RegionID]
    public let removedRegionIDs: [RegionID]
    /// Empty when no current sample exists. affectedRegionIDs still identifies unconfirmed regions.
    public let evaluations: [RegionEvaluation]
}
public enum GeofenceEvent: Equatable, Sendable {
    /// Background provider evaluation errors, distinct from import errors thrown by install.
    case evaluationFailed(GeofenceError)
    case baseline(RegionEvaluation)
    case entered(RegionEvaluation)
    case exited(RegionEvaluation)
    case datasetChanged(DatasetChange)
    case locationAvailabilityChanged(LocationAvailability)
}

/// Every subscriber gets an independent, ordered, unbounded stream. Cancel when no longer needed.
/// Queries run on the engine actor; the host owns foreground lifecycle and permission prompts.
public protocol GeofenceClient: Sendable {
    func events() async -> AsyncStream<GeofenceEvent>
    func installSnapshot(from source: URL) async throws -> InstallResult
    func query(coordinate: Coordinate, in region: RegionID) async throws -> GeometryQueryResult
    func evaluate(location: LocationSample) async throws -> [RegionEvaluation]
    func startMonitoring(mode: LocationSourceMode) async throws
    func stopMonitoring() async
    func updateAvailability(_ availability: LocationAvailability) async throws
}
public extension GeofenceClient {
    /// Convenience without revision metadata. Use query for snapshot attribution.
    func contains(coordinate: Coordinate, in region: RegionID) async throws -> Bool {
        try await query(coordinate: coordinate, in: region).membership == .inside
    }
    func evaluate(location: CLLocation) async throws -> [RegionEvaluation] {
        try await evaluate(location: LocationSample(
            coordinate: Coordinate(longitude: location.coordinate.longitude, latitude: location.coordinate.latitude),
            timestamp: location.timestamp, horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed >= 0 ? location.speed : nil))
    }
}
