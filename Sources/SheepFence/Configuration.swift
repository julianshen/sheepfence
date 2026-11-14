import Foundation

public struct GeofenceConfiguration: Equatable, Sendable {
    /// A product decision: callers must explicitly select the validity window.
    public let downloadPolicy: DownloadPolicy
    public let sampling: SamplingMode
    public let maximumLocationAge: TimeInterval
    public let boundaryBufferMeters: Double
    public let maximumFutureSkew: TimeInterval
    public let expectedDatasetIDs: Set<String>

    public init(maximumLocationAge: TimeInterval, boundaryBufferMeters: Double = 0, maximumFutureSkew: TimeInterval = 0, expectedDatasetIDs: Set<String> = [], downloadPolicy: DownloadPolicy = .standard, sampling: SamplingMode = .fixed(.standard)) throws {
        guard maximumLocationAge.isFinite, maximumLocationAge > 0 else {
            throw GeofenceError.invalidConfiguration("maximumLocationAge must be finite and positive")
        }
        guard boundaryBufferMeters.isFinite, boundaryBufferMeters >= 0 else {
            throw GeofenceError.invalidConfiguration("boundaryBufferMeters must be finite and nonnegative")
        }
        guard maximumFutureSkew.isFinite, maximumFutureSkew >= 0, expectedDatasetIDs.allSatisfy({ !$0.isEmpty }) else {
            throw GeofenceError.invalidConfiguration("Invalid future skew or expected dataset ID")
        }
        self.downloadPolicy = downloadPolicy; self.sampling = sampling
        self.maximumFutureSkew = maximumFutureSkew
        self.expectedDatasetIDs = expectedDatasetIDs
        self.maximumLocationAge = maximumLocationAge
        self.boundaryBufferMeters = boundaryBufferMeters
    }
}
