import Foundation

protocol SnapshotStore: Sendable {
    func loadCommittedSnapshots() async throws -> [ValidatedSnapshot]
    /// Serialize revision comparison and save together. Never expose NSManagedObject.
    func commit(_ snapshot: ValidatedSnapshot) async throws -> SnapshotCommit
}
struct SnapshotCommit: Sendable {
    let result: InstallResult
    let effectiveSnapshot: ValidatedSnapshot
}
