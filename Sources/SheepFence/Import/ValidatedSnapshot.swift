import Foundation

/// Internal, fully validated input. Only the decoder and test builders construct these.
struct ValidatedSnapshot: Equatable, Codable, Sendable {
    let metadata: DatasetMetadata
    let sourceBytes: Data
    let sha256: Data
    let regions: [Region]
}
