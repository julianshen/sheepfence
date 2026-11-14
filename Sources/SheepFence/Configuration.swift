import Foundation

public struct GeofenceConfiguration: Equatable, Sendable {
    /// A product decision: callers must explicitly select the validity window.
    public let maximumLocationAge: TimeInterval
    public let boundaryBufferMeters: Double

    public init(maximumLocationAge: TimeInterval, boundaryBufferMeters: Double = 0) throws {
        guard maximumLocationAge.isFinite, maximumLocationAge > 0 else {
            throw GeofenceError.invalidConfiguration("maximumLocationAge must be finite and positive")
        }
        guard boundaryBufferMeters.isFinite, boundaryBufferMeters >= 0 else {
            throw GeofenceError.invalidConfiguration("boundaryBufferMeters must be finite and nonnegative")
        }
        self.maximumLocationAge = maximumLocationAge
        self.boundaryBufferMeters = boundaryBufferMeters
    }
}
