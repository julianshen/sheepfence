import Foundation
import Testing
@testable import SheepFence

actor StoreReadProbe: SnapshotStore {
    let base: CoreDataSnapshotStore
    private(set) var calls = 0
    init(_ base: CoreDataSnapshotStore) { self.base = base }
    func loadCommittedSnapshots() async throws -> [ValidatedSnapshot] { calls += 1; return try await base.loadCommittedSnapshots() }
    func commit(_ snapshot: ValidatedSnapshot) async throws -> SnapshotCommit { calls += 1; return try await base.commit(snapshot) }
}

@Suite struct AcceptanceTests {
    @Test func campusGardenMovementAndJitterUseProductionGeometry() async throws {
        let engine = try runtime(store: CoreDataSnapshotStore(inMemory: true))
        let fixture = try #require(Bundle.module.url(forResource: "campus-v3", withExtension: "geojson"))
        _ = try await engine.install(data: Data(contentsOf: fixture))
        _ = try await engine.evaluate(location: location(10.001, lat: 20.002, at: 1100))
        let stream = await engine.events()
        let collector = Task { () -> [GeofenceEvent] in
            var events: [GeofenceEvent] = []
            for await event in stream {
                if case .locationAvailabilityChanged = event { break }
                events.append(event)
            }
            return events
        }
        let inside = try await engine.evaluate(location: location(10.003, lat: 20.002, at: 1101))
        _ = try await engine.evaluate(location: location(10.003, lat: 20.002, at: 1102))
        let garden = try #require(inside.first { $0.regionID.featureID == "garden" })
        for (offset, longitude) in [10.00199, 10.00201, 10.00199].enumerated() {
            let result = try await engine.evaluate(location: location(longitude, lat: 20.002, at: 1103 + Double(offset), accuracy: 10))
            let uncertain = try #require(result.first { $0.regionID.featureID == "garden" })
            #expect(uncertain.observation == .boundaryUncertain)
            // Last confirmed timestamp comes from the repeated confirmable sample.
            #expect(uncertain.lastConfirmed?.observedAt == Date(timeIntervalSince1970: 1102))
            #expect(uncertain.lastConfirmed?.membership == garden.lastConfirmed?.membership)
        }
        try await engine.updateAvailability(LocationAvailability(reason: .servicesDisabled))
        let events = await collector.value
        #expect(events.count == 1)
        if case .entered(let entry) = events.first { #expect(entry.regionID.featureID == "garden") }
        else { Issue.record("Expected exactly one garden enter") }
    }

    @Test func holeAndSecondComponentQueryThroughStoreAndEngine() async throws {
        let engine = try runtime(store: CoreDataSnapshotStore(inMemory: true))
        let shell = [[10.0,20.0],[10.01,20],[10.01,20.01],[10,20.01],[10,20]]
        let hole = [[10.002,20.002],[10.004,20.002],[10.004,20.004],[10.002,20.004],[10.002,20.002]]
        let second = [[10.02,20.0],[10.03,20],[10.03,20.01],[10.02,20.01],[10.02,20]]
        let data = try JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "geofenceSchema": 1,
            "dataset": ["id": "parts", "revision": 1, "generatedAt": "2026-11-14T00:00:00Z"],
            "features": [["type": "Feature", "id": "r", "properties": [:],
                          "geometry": ["type": "MultiPolygon", "coordinates": [[shell, hole], [second]]]]]])
        _ = try await engine.install(data: data)
        let id = RegionID(datasetID: "parts", featureID: "r")
        #expect(try await engine.query(coordinate: Coordinate(longitude: 10.003, latitude: 20.003), in: id).membership == .outside)
        #expect(try await engine.query(coordinate: Coordinate(longitude: 10.002, latitude: 20.003), in: id).membership == .inside)
        #expect(try await engine.query(coordinate: Coordinate(longitude: 10.025, latitude: 20.005), in: id).membership == .inside)
    }

    func runtime(store: any SnapshotStore, restored: [ValidatedSnapshot] = []) throws -> GeofenceEngine {
        GeofenceEngine(configuration: try GeofenceConfiguration(maximumLocationAge: 1000), store: store,
                       source: UnusedSource(), decoder: { try GeoJSONDecoder.decode($0) },
                       geometry: GeometryOperations(contains: { Geometry.contains($0, in: $1) }, distance: { Geometry.distanceToBoundary($0, in: $1) }, candidate: { Geometry.isCandidate($0, radiusMeters: $1, bounds: $2) }),
                       clock: FixedClock(time: Date(timeIntervalSince1970: 2000)), snapshots: restored)
    }
    func location(_ lon: Double, lat: Double = 20, at timestamp: Double, accuracy: Double = 1) -> LocationSample {
        LocationSample(coordinate: Coordinate(longitude: lon, latitude: lat), timestamp: Date(timeIntervalSince1970: timestamp), horizontalAccuracy: accuracy)
    }
    @Test func separatedHundredRegionsUsesOnlyMemoryForQueries() async throws {
        let base = try CoreDataSnapshotStore(inMemory: true)
        let store = StoreReadProbe(base), engine = try runtime(store: store)
        _ = try await engine.install(data: CapacityFixtureFactory.make(overlapping: false))
        let reads = await store.calls
        let coreDataReads = base.readCountSnapshot
        for index in 0..<100 {
            let result = try await engine.evaluate(location: location(10 + Double(index)*0.05, at: 1100 + Double(index)))
            let inside = result.filter { $0.observation == .confirmed(.inside) }.map(\.regionID.featureID)
            #expect(inside == [String(format: "region-%03d", index)])
            #expect(result.count == 100)
        }
        let outside = try await engine.evaluate(location: location(0, lat: 0, at: 1300))
        #expect(outside.allSatisfy { $0.observation == .confirmed(.outside) })
        // Point lies outside the first raw bbox but its uncertainty disk reaches the edge.
        let uncertain = try await engine.evaluate(location: location(10.01001, at: 1301, accuracy: 10))
        #expect(uncertain.first { $0.regionID.featureID == "region-000" }?.observation == .boundaryUncertain)
        #expect(await store.calls == reads)
        #expect(base.readCountSnapshot == coreDataReads)
    }
    @Test func overlappingHundredRegionsCrossExactlyOnceEach() async throws {
        let base = try CoreDataSnapshotStore(inMemory: true)
        let store = StoreReadProbe(base), engine = try runtime(store: store)
        _ = try await engine.install(data: CapacityFixtureFactory.make(overlapping: true))
        let stream = await engine.events()
        let collected = Task { () -> [GeofenceEvent] in
            var events: [GeofenceEvent] = []
            for await event in stream {
                if case .locationAvailabilityChanged = event { break }
                events.append(event)
            }
            return events
        }
        let reads = await store.calls
        let coreDataReads = base.readCountSnapshot
        _ = try await engine.evaluate(location: location(9, at: 1100))
        let inside = try await engine.evaluate(location: location(10, at: 1101))
        #expect(inside.filter { $0.observation == .confirmed(.inside) }.count == 100)
        #expect(Set(inside.map(\.regionID)).count == 100)
        _ = try await engine.evaluate(location: location(10, at: 1102))
        _ = try await engine.evaluate(location: location(9, at: 1103))
        try await engine.updateAvailability(LocationAvailability(reason: .servicesDisabled))
        let events = await collected.value
        var enters: [RegionID: Int] = [:], exits: [RegionID: Int] = [:]
        for event in events {
            if case .entered(let e) = event { enters[e.regionID, default: 0] += 1; #expect(e.revision == 1) }
            if case .exited(let e) = event { exits[e.regionID, default: 0] += 1; #expect(e.revision == 1) }
        }
        #expect(enters.count == 100 && exits.count == 100)
        #expect(enters.values.allSatisfy { $0 == 1 } && exits.values.allSatisfy { $0 == 1 })
        #expect(await store.calls == reads)
        #expect(base.readCountSnapshot == coreDataReads)
    }
    @Test func bundledFixturePersistsAndRejectsInvalidReplacement() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("dataset.sqlite")
        let store = try CoreDataSnapshotStore(url: url), engine = try runtime(store: store)
        let fixture = try #require(Bundle.module.url(forResource: "campus-v3", withExtension: "geojson"))
        let bytes = try Data(contentsOf: fixture)
        _ = try await engine.install(data: bytes)
        for name in ["garden", "campus"] {
            #expect(try await engine.query(coordinate: Coordinate(longitude: 10.003, latitude: 20.002), in: RegionID(datasetID: "com.example.campus", featureID: name)).membership == .inside)
        }
        await #expect(throws: GeofenceError.self) { try await engine.install(data: Data("invalid".utf8)) }
        let reopened = try CoreDataSnapshotStore(url: url)
        let restored = try await reopened.loadCommittedSnapshots()
        let restoredEngine = try runtime(store: reopened, restored: restored)
        #expect(try await restoredEngine.query(coordinate: Coordinate(longitude: 10.003, latitude: 20.002), in: RegionID(datasetID: "com.example.campus", featureID: "garden")).revision == 3)
        #expect(try await restoredEngine.evaluate(location: location(10.003, lat: 20.002, at: 1100)).allSatisfy { $0.observation == .confirmed(.inside) })
    }
}
