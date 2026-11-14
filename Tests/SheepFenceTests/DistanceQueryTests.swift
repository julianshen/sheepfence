import Foundation
import Testing
@testable import SheepFence

struct DistanceQueryTests {
    @Test func distanceUsesNamedDisabledRegionAndCommittedRevision() async throws {
        let h = EngineIntegrationTests(), snapshot = EngineIntegrationTests().snapshot(1, enabled: false)
        let engine = try h.engine([snapshot])
        _ = try await engine.install(data: snapshot.sourceBytes)
        let result = try await engine.distance(from: .init(longitude: 0.5, latitude: 0.5), to: h.id)
        #expect(result.revision == 1)
        #expect(result.membership == .inside)
        #expect(result.distanceToRegionMeters == 0)
        #expect((result.distanceToBoundaryMeters ?? 0) > 50_000)
        let before = await engine.currentState()
        _ = try await engine.distance(from: .init(longitude: -10, latitude: 0.5), to: h.id)
        #expect(await engine.currentState() == before)
    }
    @Test func unsupportedAndInvalidCoordinatesAreDistinct() async throws {
        let h = EngineIntegrationTests(), snapshot = EngineIntegrationTests().snapshot(1)
        let engine = try h.engine([snapshot])
        _ = try await engine.install(data: snapshot.sourceBytes)
        let distant = try await engine.distance(from: .init(longitude: -10, latitude: 0), to: h.id)
        #expect(distant.boundaryDistance == .unsupported(.outsideLocalModelRange))
        #expect(distant.distanceToRegionMeters == nil)
        await #expect(throws: GeofenceError.invalidCoordinate) {
            try await engine.distance(from: .init(longitude: .nan, latitude: 0), to: h.id)
        }
    }
}

struct SDKCatalogIntegrationTests {
    @Test func removalPublishesAfterCommitAndReimportCanRestoreDataset() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("data.sqlite")
        let store = try CoreDataSnapshotStore(url: url)
        let engine = GeofenceEngine(configuration: try .init(maximumLocationAge: 60), store: store,
            source: UnusedSource(), decoder: { try GeoJSONDecoder.decode($0) },
            geometry: .init(contains: { Geometry.contains($0, in: $1) }, distance: { Geometry.distanceToBoundary($0, in: $1) }))
        let fixture = try #require(Bundle.module.url(forResource: "campus-v3", withExtension: "geojson"))
        let data = try Data(contentsOf: fixture)
        _ = try await engine.install(data: data)
        let datasetID = "com.example.campus"
        #expect(await engine.datasets().first?.metadata.revision == 3)
        #expect(try await engine.regions(in: datasetID).count == 2)
        let stream = try await engine.eventStream()
        var iterator = stream.makeAsyncIterator()
        _ = try await iterator.next()
        let removed = try await engine.removeDataset(id: datasetID)
        #expect(removed.wasPresent)
        #expect(removed.removedRegionIDs.count == 2)
        #expect(try await iterator.next() == .datasetRemoved(removed))
        #expect(try await store.loadCommittedSnapshots().isEmpty)
        #expect(await engine.currentState().readiness == .noDatasets)
        #expect(try await engine.removeDataset(id: datasetID).wasPresent == false)
        _ = try await engine.install(data: data)
        let restored = try CoreDataSnapshotStore(url: url)
        #expect(try await restored.loadCommittedSnapshots().first?.metadata.revision == 3)
    }
}
