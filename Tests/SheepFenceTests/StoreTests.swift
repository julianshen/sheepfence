import Foundation
import Testing
@testable import SheepFence

@Suite struct StoreTests {
    @Test func sqliteRoundTripPreservesCompleteSnapshotAndReopens() async throws {
        let url = try makeSQLiteURL()
        let snapshot = PreparedSnapshotBuilder.make(
            id: "campus", revision: 3,
            regions: [makeRegion(datasetID: "campus", featureID: "campus"), makeRegion(datasetID: "campus", featureID: "garden")]
        )

        do {
            let store = try CoreDataSnapshotStore(url: url)
            let commit = try await store.commit(snapshot)
            #expect(commit.result.outcome == .installed)
            #expect(commit.result.activeRevision == 3)
            #expect(commit.effectiveSnapshot == snapshot)
        }

        let reopened = try CoreDataSnapshotStore(url: url)
        #expect(try await reopened.loadCommittedSnapshots() == [snapshot])
    }

    @Test func replacementRemovesOldRegionsAndAllowsEmptyDataset() async throws {
        let store = try CoreDataSnapshotStore(inMemory: true)
        let first = makeRegion(datasetID: "test", featureID: "first")
        let second = makeRegion(datasetID: "test", featureID: "second")
        _ = try await store.commit(PreparedSnapshotBuilder.make(revision: 1, regions: [first, second]))

        let replacement = PreparedSnapshotBuilder.make(revision: 2, regions: [second])
        _ = try await store.commit(replacement)
        #expect(try await store.loadCommittedSnapshots() == [replacement])

        let empty = PreparedSnapshotBuilder.make(revision: 3, regions: [])
        _ = try await store.commit(empty)
        #expect(try await store.loadCommittedSnapshots() == [empty])
    }

    @Test func revisionRulesPreserveCommittedSnapshot() async throws {
        let store = try CoreDataSnapshotStore(inMemory: true)
        let current = PreparedSnapshotBuilder.make(revision: 3, bytes: Data("current".utf8))
        _ = try await store.commit(current)

        let retry = try await store.commit(current)
        #expect(retry.result.outcome == .unchanged)
        #expect(retry.effectiveSnapshot == current)

        let older = try await store.commit(PreparedSnapshotBuilder.make(revision: 2, bytes: Data("older".utf8)))
        #expect(older.result.outcome == .olderVersionSkipped)
        #expect(older.result.activeRevision == 3)
        #expect(older.effectiveSnapshot == current)

        await #expect(throws: GeofenceError.revisionConflict(datasetID: "test", revision: 3)) {
            _ = try await store.commit(PreparedSnapshotBuilder.make(revision: 3, bytes: Data("different".utf8)))
        }
        #expect(try await store.loadCommittedSnapshots() == [current])
    }

    @Test func failedSaveRollsBackMemoryAndSQLite() async throws {
        let url = try makeSQLiteURL()
        let current = PreparedSnapshotBuilder.make(revision: 3, bytes: Data("current".utf8))
        let store = try CoreDataSnapshotStore(url: url, beforeSave: { revision in
            if revision == 4 { throw GeofenceError.storageFailed("injected save failure") }
        })
        _ = try await store.commit(current)

        await #expect(throws: GeofenceError.storageFailed("injected save failure")) {
            _ = try await store.commit(PreparedSnapshotBuilder.make(revision: 4, regions: [makeRegion(datasetID: "test", featureID: "new")]))
        }
        #expect(try await store.loadCommittedSnapshots() == [current])

        let reopened = try CoreDataSnapshotStore(url: url)
        #expect(try await reopened.loadCommittedSnapshots() == [current])
    }

    @Test func heldOlderTaskCannotOverwriteNewerCommit() async throws {
        let gate = RevisionGate()
        let coordinated = try CoreDataSnapshotStore(inMemory: true, beforeCommit: { revision in
            if revision == 4 { await gate.hold() }
        })

        let revisionFour = PreparedSnapshotBuilder.make(revision: 4)
        let revisionFive = PreparedSnapshotBuilder.make(revision: 5)
        let held = Task { try await coordinated.commit(revisionFour) }
        await gate.waitUntilHeld()

        let fifth = try await coordinated.commit(revisionFive)
        #expect(fifth.result.outcome == .installed)
        await gate.release()
        let fourth = try await held.value
        #expect(fourth.result.outcome == .olderVersionSkipped)
        #expect(fourth.effectiveSnapshot == revisionFive)
        #expect(try await coordinated.loadCommittedSnapshots() == [revisionFive])
    }

    @Test func failedHigherRevisionDoesNotBlockHeldLowerRevision() async throws {
        let gate = RevisionGate()
        let store = try CoreDataSnapshotStore(
            inMemory: true,
            beforeCommit: { revision in if revision == 4 { await gate.hold() } },
            beforeSave: { revision in if revision == 5 { throw GeofenceError.storageFailed("v5 failed") } }
        )
        let revisionFour = PreparedSnapshotBuilder.make(revision: 4)
        let held = Task { try await store.commit(revisionFour) }
        await gate.waitUntilHeld()

        await #expect(throws: GeofenceError.storageFailed("v5 failed")) {
            _ = try await store.commit(PreparedSnapshotBuilder.make(revision: 5))
        }
        await gate.release()
        let fourth = try await held.value
        #expect(fourth.result.outcome == .installed)
        #expect(try await store.loadCommittedSnapshots() == [revisionFour])
    }
}

private func makeSQLiteURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("snapshots.sqlite")
}

private func makeRegion(datasetID: String, featureID: String) -> Region {
    let coordinates = [
        Coordinate(longitude: 10, latitude: 20), Coordinate(longitude: 10.001, latitude: 20),
        Coordinate(longitude: 10.001, latitude: 20.001), Coordinate(longitude: 10, latitude: 20.001),
        Coordinate(longitude: 10, latitude: 20)
    ]
    return Region(
        id: RegionID(datasetID: datasetID, featureID: featureID), name: featureID,
        enabled: true, priority: featureID == "garden" ? 10 : 0,
        geometry: RegionGeometry(polygons: [Polygon(rings: [coordinates])]),
        bounds: [RegionBounds(minLongitude: 10, minLatitude: 20, maxLongitude: 10.001, maxLatitude: 20.001)]
    )
}

private actor RevisionGate {
    private var held = false
    private var holdContinuation: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []

    func hold() async {
        await withCheckedContinuation { continuation in
            held = true
            holdContinuation = continuation
            observers.forEach { $0.resume() }
            observers.removeAll()
        }
    }

    func waitUntilHeld() async {
        if held { return }
        await withCheckedContinuation { continuation in
            observers.append(continuation)
        }
    }

    func release() {
        holdContinuation?.resume()
        holdContinuation = nil
    }
}
