import Foundation

public enum LocationSourceMode: Sendable { case hostProvided, sdkManaged }
public struct LocationSample: Equatable, Sendable {
    public let coordinate: Coordinate
    public let timestamp: Date
    public let horizontalAccuracy: Double
    public let speed: Double?
    public init(coordinate: Coordinate, timestamp: Date, horizontalAccuracy: Double, speed: Double? = nil) {
        self.coordinate = coordinate; self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy; self.speed = speed
    }
}
public struct LocationAvailability: Equatable, Sendable {
    public let reason: LocationUnavailableReason?
    public let reducedAccuracy: Bool
    public init(reason: LocationUnavailableReason? = nil, reducedAccuracy: Bool = false) {
        self.reason = reason; self.reducedAccuracy = reducedAccuracy
    }
}
struct SamplingSettings: Equatable, Sendable {
    let distanceFilter: Double
    let desiredAccuracy: Double
}
enum LocationProviderEvent: Sendable {
    case location(LocationSample)
    case availability(LocationAvailability)
}
@MainActor protocol LocationProvider: AnyObject {
    var onEvent: (@MainActor @Sendable (LocationProviderEvent) -> Void)? { get set }
    func start()
    func stop()
    func apply(_ settings: SamplingSettings)
}
