import Foundation

/// Persistence boundary. Implementations must serialize revision checks and commits.
/// Queries use an immutable memory snapshot, never this interface directly.
protocol SnapshotStore: Sendable {
    func loadCommittedSnapshots() async throws -> [StoredSnapshot]
    func commit(_ snapshot: StoredSnapshot) async throws -> InstallResult
}

/// Original bytes are retained to distinguish exact retries from revision conflicts.
/// The Core Data implementation must additionally persist validated regions and bounds.
struct StoredSnapshot: Sendable {
    let metadata: DatasetMetadata
    let sourceBytes: Data
    let sha256: Data
}
