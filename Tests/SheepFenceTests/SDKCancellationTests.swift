import Foundation
import Testing
@testable import SheepFence

private actor Barrier {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var reachedCount = 0
    private var reachedWaiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilReached(_ count: Int = 1) async {
        if reachedCount >= count { return }
        await withCheckedContinuation { cont in
            if reachedCount >= count { cont.resume() } else { reachedWaiters.append(cont) }
        }
    }

    func arrive() async {
        reachedCount += 1
        if !reachedWaiters.isEmpty {
            reachedWaiters.removeFirst().resume()
        }
        if open { return }
        await withCheckedContinuation { cont in
            if open { cont.resume() } else { waiters.append(cont) }
        }
    }

    func release() {
        open = true
        for w in waiters { w.resume() }
        waiters.removeAll()
        for w in reachedWaiters { w.resume() }
        reachedWaiters.removeAll()
    }
}



private struct CancellationUnusedSource: SnapshotSource {
    func read(from url: URL) async throws -> Data { throw GeofenceError.unsupportedSource(url) }
}

private struct CancellationFixedClock: GeofenceClock {
    let time: Date
    func now() -> Date { time }
}

private actor CancellationTestStore: SnapshotStore {
    var installed: [String: ValidatedSnapshot] = [:]
    let commitBarrier: Barrier?
    let blockDatasetID: String?

    init(commitBarrier: Barrier? = nil, blockDatasetID: String? = nil) {
        self.commitBarrier = commitBarrier
        self.blockDatasetID = blockDatasetID
    }

    func loadCommittedSnapshots() -> [ValidatedSnapshot] { Array(installed.values) }

    func commit(_ snapshot: ValidatedSnapshot) async throws -> SnapshotCommit {
        if let commitBarrier, blockDatasetID == nil || blockDatasetID == snapshot.metadata.id {
            await commitBarrier.arrive()
        }
        let id = snapshot.metadata.id
        if let old = installed[id], old.metadata.revision >= snapshot.metadata.revision {
            let outcome: InstallOutcome
            if old.metadata.revision > snapshot.metadata.revision { outcome = .olderVersionSkipped }
            else {
                guard old.sourceBytes == snapshot.sourceBytes else {
                    throw GeofenceError.revisionConflict(datasetID: id, revision: snapshot.metadata.revision)
                }
                outcome = .unchanged
            }
            return SnapshotCommit(result: InstallResult(dataset: snapshot.metadata, activeRevision: old.metadata.revision, outcome: outcome), effectiveSnapshot: old)
        }
        installed[id] = snapshot
        return SnapshotCommit(result: InstallResult(dataset: snapshot.metadata, activeRevision: snapshot.metadata.revision, outcome: .installed), effectiveSnapshot: snapshot)
    }

    func removeDataset(id: String) async throws -> DatasetRemovalResult {
        let removed = installed.removeValue(forKey: id)
        return DatasetRemovalResult(
            datasetID: id,
            removedRegionIDs: (removed?.regions.map(\.id) ?? []).sorted { $0.featureID < $1.featureID },
            wasPresent: removed != nil
        )
    }

    func snapshot(for id: String) -> ValidatedSnapshot? { installed[id] }
}

@Suite struct SDKCancellationTests {
    private func engine(
        store: any SnapshotStore,
        candidates: [ValidatedSnapshot],
        onTransactionQueued: @escaping @Sendable () -> Void = {}
    ) throws -> GeofenceEngine {
        let byBytes = Dictionary(candidates.map { ($0.sourceBytes, $0) }, uniquingKeysWith: { _, b in b })
        return GeofenceEngine(
            configuration: try GeofenceConfiguration(maximumLocationAge: 500),
            store: store,
            source: CancellationUnusedSource(),
            decoder: { data in
                guard let snapshot = byBytes[data] else {
                    throw GeofenceError.invalidSnapshot(regionID: nil, path: "$", reason: "test invalid")
                }
                return snapshot
            },
            geometry: GeometryOperations(
                contains: { point, geometry in point.longitude > geometry.polygons[0].rings[0][0].longitude },
                distance: { point, geometry in abs(point.longitude - geometry.polygons[0].rings[0][0].longitude) * 100 }
            ),
            clock: CancellationFixedClock(time: Date(timeIntervalSince1970: 1000)),
            onTransactionQueued: onTransactionQueued
        )
    }

    private func snapshot(_ revision: Int, bytes: Data? = nil) -> ValidatedSnapshot {
        let id = RegionID(datasetID: "d", featureID: "r")
        let ring = [Coordinate(longitude: 0, latitude: 0), Coordinate(longitude: 1, latitude: 0), Coordinate(longitude: 1, latitude: 1), Coordinate(longitude: 0, latitude: 1), Coordinate(longitude: 0, latitude: 0)]
        let region = Region(id: id, name: "r", enabled: true, priority: 0, geometry: RegionGeometry(polygons: [Polygon(rings: [ring])]), bounds: [])
        return PreparedSnapshotBuilder.make(id: "d", revision: revision, regions: [region], bytes: bytes ?? Data([UInt8(revision)]))
    }

    @Test func queuedInstallCancelledBeforeBeginRetainsOldSnapshot() async throws {
        let barrier = Barrier()
        let v1 = snapshot(1)
        let v2 = snapshot(2)
        let store = CancellationTestStore(commitBarrier: barrier, blockDatasetID: "d")
        let (queuedStream, queuedContinuation) = AsyncStream.makeStream(of: Void.self)
        var queuedIterator = queuedStream.makeAsyncIterator()
        let engine = try engine(store: store, candidates: [v1, v2], onTransactionQueued: { queuedContinuation.yield() })

        let first = Task { try await engine.install(data: v1.sourceBytes) }
        await queuedIterator.next() // first queued (installTail assigned), before wait/commit
        await barrier.waitUntilReached(1) // first blocked inside store.commit

        let second = Task { try await engine.install(data: v2.sourceBytes) }
        await queuedIterator.next() // second queued-after-decode while first commit blocked; not yet begun
        second.cancel()
        await barrier.release()

        let firstResult = try await first.value
        #expect(firstResult.outcome == .installed)
        #expect(firstResult.activeRevision == 1)

        await #expect(throws: CancellationError.self) { try await second.value }

        #expect(await store.snapshot(for: "d")?.metadata.revision == 1)
        let summaries = await engine.datasets()
        #expect(summaries.count == 1)
        #expect(summaries.first?.metadata.revision == 1)
    }

    @Test func cancellationAfterCommitBeginsStillCompletesAndPublishes() async throws {
        let barrier = Barrier()
        let v1 = snapshot(1)
        let store = CancellationTestStore(commitBarrier: barrier, blockDatasetID: "d")
        let engine = try engine(store: store, candidates: [v1])

        let task = Task { try await engine.install(data: v1.sourceBytes) }
        await barrier.waitUntilReached(1) // inside store.commit; engine gate.begin() already passed
        task.cancel()
        await barrier.release()

        let result = try await task.value
        #expect(result.outcome == .installed)
        #expect(result.activeRevision == 1)
        #expect(await store.snapshot(for: "d")?.metadata.revision == 1)
        let summaries = await engine.datasets()
        #expect(summaries.count == 1)
        #expect(summaries.first?.metadata.revision == 1)
    }
}
