import CoreLocation
import Foundation

public enum GeofenceEvent: Equatable, Sendable {
    /// First or resumed confirmed state; never an inferred crossing.
    case baseline(RegionEvaluation)
    case entered(RegionEvaluation)
    case exited(RegionEvaluation)
    case datasetChanged(DatasetMetadata)
    case locationAvailabilityChanged(LocationUnavailableReason?)
}

/// Proposed integration surface from spec 0.3. A concrete engine is not yet implemented.
/// The host owns permission prompts and calls stopMonitoring on leaving the foreground.
@MainActor
public protocol GeofenceClient: AnyObject {
    var events: AsyncStream<GeofenceEvent> { get }

    /// Accepts local/bundle file URLs or HTTPS URLs; each file is a complete snapshot.
    func installSnapshot(from source: URL) async throws -> InstallResult
    func contains(coordinate: CLLocationCoordinate2D, in region: RegionID) throws -> Bool
    func evaluate(location: CLLocation) throws -> [RegionEvaluation]
    func startMonitoring()
    func stopMonitoring()
}
