import Foundation

protocol SnapshotStore: Sendable {
    func loadCommittedSnapshots() async throws -> [ValidatedSnapshot]
    /// Serialize revision comparison and save together. Never expose NSManagedObject.
    func commit(_ snapshot: ValidatedSnapshot) async throws -> SnapshotCommit
    /// Transactional removal. Commits durably before returning; removing a missing
    /// ID is an idempotent no-op (wasPresent false). A failed deletion preserves
    /// the old data. Never expose NSManagedObject.
    func removeDataset(id: String) async throws -> DatasetRemovalResult
}

/// Canonical RegionID ordering for removal results: datasetID first, then featureID.
func regionIDOrder(_ a: RegionID, _ b: RegionID) -> Bool {
    a.datasetID == b.datasetID ? a.featureID < b.featureID : a.datasetID < b.datasetID
}
struct SnapshotCommit: Sendable {
    let result: InstallResult
    let effectiveSnapshot: ValidatedSnapshot
}
