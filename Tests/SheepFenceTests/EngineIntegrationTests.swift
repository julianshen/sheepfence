import Foundation
import Testing
@testable import SheepFence

struct FixedClock: GeofenceClock { let time: Date; func now() -> Date { time } }
struct UnusedSource: SnapshotSource { func read(from url: URL) async throws -> Data { throw GeofenceError.unsupportedSource(url) } }
actor TestSnapshotStore: SnapshotStore {
    var installed: [String: ValidatedSnapshot] = [:]
    var fail = false
    var commits = 0
    func loadCommittedSnapshots() -> [ValidatedSnapshot] { Array(installed.values) }
    func setFailure(_ value: Bool) { fail = value }
    func commit(_ snapshot: ValidatedSnapshot) throws -> SnapshotCommit {
        commits += 1
        if fail { throw GeofenceError.storageFailed("injected") }
        let id = snapshot.metadata.id
        if let old = installed[id], old.metadata.revision >= snapshot.metadata.revision {
            let outcome: InstallOutcome
            if old.metadata.revision > snapshot.metadata.revision { outcome = .olderVersionSkipped }
            else {
                guard old.sourceBytes == snapshot.sourceBytes else { throw GeofenceError.revisionConflict(datasetID: id, revision: snapshot.metadata.revision) }
                outcome = .unchanged
            }
            return SnapshotCommit(result: InstallResult(dataset: snapshot.metadata, activeRevision: old.metadata.revision, outcome: outcome), effectiveSnapshot: old)
        }
        installed[id] = snapshot
        return SnapshotCommit(result: InstallResult(dataset: snapshot.metadata, activeRevision: snapshot.metadata.revision, outcome: .installed), effectiveSnapshot: snapshot)
    }
}

@Suite struct EngineIntegrationTests {
    let id = RegionID(datasetID: "d", featureID: "r")
    func snapshot(_ revision: Int, enabled: Bool = true, edge: Double = 0, bytes: Data? = nil, empty: Bool = false) -> ValidatedSnapshot {
        let ring = [Coordinate(longitude: edge, latitude: 0), Coordinate(longitude: edge+1, latitude: 0), Coordinate(longitude: edge+1, latitude: 1), Coordinate(longitude: edge, latitude: 1), Coordinate(longitude: edge, latitude: 0)]
        let region = Region(id: id, name: "r", enabled: enabled, priority: 0, geometry: RegionGeometry(polygons: [Polygon(rings: [ring])]), bounds: [])
        return PreparedSnapshotBuilder.make(id: "d", revision: revision, regions: empty ? [] : [region], bytes: bytes ?? Data([UInt8(revision)]))
    }
    func engine(_ candidates: [ValidatedSnapshot], store: TestSnapshotStore = TestSnapshotStore()) throws -> GeofenceEngine {
        let byBytes = Dictionary(candidates.map { ($0.sourceBytes, $0) }, uniquingKeysWith: { _, b in b })
        return GeofenceEngine(configuration: try GeofenceConfiguration(maximumLocationAge: 500), store: store, source: UnusedSource(), decoder: { data in
            guard let snapshot = byBytes[data] else { throw GeofenceError.invalidSnapshot(regionID: nil, path: "$", reason: "test invalid") }
            return snapshot
        }, geometry: GeometryOperations(contains: { point, geometry in point.longitude > geometry.polygons[0].rings[0][0].longitude }, distance: { point, geometry in abs(point.longitude - geometry.polygons[0].rings[0][0].longitude) * 100 }), clock: FixedClock(time: Date(timeIntervalSince1970: 1000)))
    }
    func sample(_ longitude: Double, _ time: Double = 900, accuracy: Double = 1) -> LocationSample {
        LocationSample(coordinate: Coordinate(longitude: longitude, latitude: 0.5), timestamp: Date(timeIntervalSince1970: time), horizontalAccuracy: accuracy)
    }
    func collectUntilMarker(_ engine: GeofenceEngine) async -> Task<[GeofenceEvent], Never> {
        let stream = await engine.events()
        return Task {
            var results: [GeofenceEvent] = []
            for await event in stream {
                if case .locationAvailabilityChanged(let value) = event, value.reason == .servicesDisabled { break }
                results.append(event)
            }
            return results
        }
    }
    @Test func noOpAndFailurePreserveStateAndEvents() async throws {
        let v1 = snapshot(1), v2 = snapshot(2), conflict = snapshot(2, bytes: Data([22]))
        let store = TestSnapshotStore()
        let engine = try engine([v1, v2, conflict], store: store)
        _ = try await engine.install(data: v2.sourceBytes)
        let collector = await collectUntilMarker(engine)
        let initial = try await engine.evaluate(location: sample(1))
        #expect(try await engine.install(data: v2.sourceBytes).outcome == .unchanged)
        #expect(try await engine.install(data: v1.sourceBytes).outcome == .olderVersionSkipped)
        await #expect(throws: GeofenceError.self) { try await engine.install(data: conflict.sourceBytes) }
        await store.setFailure(true)
        await #expect(throws: GeofenceError.self) { try await engine.install(data: v1.sourceBytes) }
        let uncertain = try await engine.evaluate(location: sample(0, 901))
        #expect(uncertain[0].lastConfirmed == initial[0].lastConfirmed)
        #expect(try await engine.query(coordinate: Coordinate(longitude: 1, latitude: 0), in: id).revision == 2)
        try await engine.updateAvailability(LocationAvailability(reason: .servicesDisabled))
        #expect(await collector.value == [.baseline(initial[0])])
    }
    @Test func changedGeometryRebasesWithinDatasetEventOnly() async throws {
        let first = snapshot(1), expanded = snapshot(2, edge: -2)
        let engine = try engine([first, expanded])
        _ = try await engine.install(data: first.sourceBytes)
        _ = try await engine.evaluate(location: sample(-1))
        let collector = await collectUntilMarker(engine)
        _ = try await engine.install(data: expanded.sourceBytes)
        let next = try await engine.evaluate(location: sample(-1, 901))
        #expect(next[0].observation == .confirmed(.inside))
        try await engine.updateAvailability(LocationAvailability(reason: .servicesDisabled))
        let events = await collector.value
        #expect(events.count == 1)
        guard case .datasetChanged(let change) = events.first else { Issue.record("Expected datasetChanged only"); return }
        #expect(change.evaluations.first?.observation == .confirmed(.inside))
        #expect(change.dataset.revision == 2)
    }
    @Test func sourceExclusivityAndStaleGeneration() async throws {
        let v1 = snapshot(1), engine = try engine([snapshot(1)])
        _ = try await engine.install(data: v1.sourceBytes)
        try await engine.startMonitoring(mode: .sdkManaged)
        let oldGeneration = await engine.monitoringGeneration()
        await #expect(throws: GeofenceError.sourceModeConflict) { try await engine.evaluate(location: sample(1)) }
        await engine.stopMonitoring()
        try await engine.startMonitoring(mode: .sdkManaged)
        #expect(try await engine.receive(sample(1), generation: oldGeneration).isEmpty)
        let newGeneration = await engine.monitoringGeneration()
        let current = try await engine.receive(sample(1), generation: newGeneration)
        #expect(current[0].observation == .confirmed(.inside))
    }
    @Test func locationInvalidityAndOrderingDoNotInventCrossings() async throws {
        let v1 = snapshot(1), engine = try engine([snapshot(1)])
        _ = try await engine.install(data: v1.sourceBytes)
        let first = try await engine.evaluate(location: sample(-1))
        #expect(try await engine.evaluate(location: sample(1, 899))[0].observation == .unavailable(.outOfOrderLocation))
        #expect(try await engine.evaluate(location: sample(1, 900))[0].observation == .unavailable(.outOfOrderLocation))
        #expect(try await engine.evaluate(location: sample(1, 1001))[0].observation == .unavailable(.futureLocation))
        #expect(try await engine.evaluate(location: sample(1, 1))[0].observation == .unavailable(.staleLocation))
        #expect(try await engine.evaluate(location: sample(1, 901, accuracy: -1))[0].lastConfirmed == first[0].lastConfirmed)
    }
    @Test func emptyDatasetIsReadyAndMissingRegionErrors() async throws {
        let empty = snapshot(1, empty: true), engine = try engine([snapshot(1, empty: true)])
        await #expect(throws: GeofenceError.datasetNotReady(nil)) { try await engine.evaluate(location: sample(1)) }
        _ = try await engine.install(data: empty.sourceBytes)
        #expect(try await engine.evaluate(location: sample(1)).isEmpty)
        await #expect(throws: GeofenceError.regionNotFound(id)) { try await engine.query(coordinate: Coordinate(longitude: 0, latitude: 0), in: id) }
    }
    @Test func concurrentInstallsKeepHighestSuccessfulRevision() async throws {
        let v4 = snapshot(4), v5 = snapshot(5), engine = try engine([snapshot(4), snapshot(5)])
        async let a = engine.install(data: v4.sourceBytes)
        async let b = engine.install(data: v5.sourceBytes)
        _ = try await (a, b)
        #expect(try await engine.query(coordinate: Coordinate(longitude: 0, latitude: 0), in: id).revision == 5)
    }
}
