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
}
protocol SnapshotSource: Sendable {
    func read(from url: URL) async throws -> Data
}
