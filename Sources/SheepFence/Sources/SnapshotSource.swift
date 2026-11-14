import Foundation

public struct DownloadPolicy: Sendable, Equatable {
    public let maximumBytes: Int
    public let timeout: TimeInterval
    public init(maximumBytes: Int, timeout: TimeInterval) throws {
        guard maximumBytes > 0, timeout.isFinite, timeout > 0 else {
            throw GeofenceError.invalidConfiguration("Download limits must be finite and positive")
        }
        self.maximumBytes = maximumBytes; self.timeout = timeout
    }

    /// Resource limits for SDK-managed downloads, not geofence tuning:
    /// 5,000,000 bytes and a 30 second transport timeout (contract freeze v1).
    public static let standard = try! DownloadPolicy(maximumBytes: 5_000_000, timeout: 30)
}
protocol SnapshotSource: Sendable {
    func read(from url: URL) async throws -> Data
}
