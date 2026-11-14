import Foundation
import Testing
import SheepFence

@Suite @MainActor struct PublicClientTests {
    @Test func publicConstructionInstallsAndRestoresOffline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("snapshot.sqlite")
        let downloads = try DownloadPolicy(maximumBytes: 1_000_000, timeout: 30)
        let sampling = try SamplingPolicyConfiguration()
        let configuration = try GeofenceConfiguration(maximumLocationAge: 60, downloadPolicy: downloads, sampling: .adaptive(sampling))
        var client: SheepFenceClient? = try await .open(storeURL: storeURL, configuration: configuration)
        let fixture = try #require(Bundle.module.url(forResource: "campus-v3", withExtension: "geojson"))
        _ = try await client!.installSnapshot(from: fixture)
        let region = RegionID(datasetID: "com.example.campus", featureID: "garden")
        let coordinate = Coordinate(longitude: 10.003, latitude: 20.002)
        #expect(try await client!.query(coordinate: coordinate, in: region).membership == .inside)
        await client!.stopMonitoring()
        client = nil
        let reopened = try await SheepFenceClient.open(storeURL: storeURL, configuration: configuration)
        #expect(try await reopened.query(coordinate: coordinate, in: region).revision == 3)
        let observations = try await reopened.evaluate(location: LocationSample(coordinate: coordinate,
            timestamp: Date(), horizontalAccuracy: 1))
        #expect(observations.results.contains { $0.regionID == region && $0.observation == .confirmed(.inside) })
        await reopened.stopMonitoring()
    }
}

@Suite @MainActor struct SDKPublicConsumerTests {
    @Test func completeOfflineConsumerFlowAndExclusiveStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("new/SDK.sqlite")
        let config = try GeofenceConfiguration(maximumLocationAge: 60)
        let client = try await SheepFenceClient.open(storeURL: url, configuration: config)
        await #expect(throws: GeofenceError.storeAlreadyOpen) {
            try await SheepFenceClient.open(storeURL: url, configuration: config)
        }
        let fixture = try #require(Bundle.module.url(forResource: "campus-v3", withExtension: "geojson"))
        let data = try Data(contentsOf: fixture)
        #expect(try await client.installSnapshot(data: data).outcome == .installed)
        #expect(try await client.installSnapshot(data: data).outcome == .unchanged)
        let id = RegionID(datasetID: "com.example.campus", featureID: "garden")
        #expect(try await client.regions().contains { $0.id == id })
        #expect(await client.datasets().first?.metadata.revision == 3)
        let coordinate = Coordinate(longitude: 10.003, latitude: 20.002)
        let sample = LocationSample(coordinate: coordinate, timestamp: Date(), horizontalAccuracy: 1)
        #expect(try await client.distance(from: coordinate, to: id).distanceToRegionMeters == 0)
        #expect(try await client.evaluate(location: sample).results.contains { $0.regionID == id && $0.observation == .confirmed(.inside) })
        #expect(await client.state().mode == nil)
        let stream = try await client.events()
        var iterator = stream.makeAsyncIterator()
        guard case .stateSnapshot? = try await iterator.next() else { Issue.record("missing initial snapshot"); return }
        try await client.startMonitoring(mode: .hostProvided)
        #expect(try await client.submit(location: sample).results.count == 2)
        try await client.updateAvailability(.init(reason: .noLocation))
        #expect(await client.state().evaluations.allSatisfy { $0.observation == .unavailable(.noLocation) })
        await client.stopMonitoring()
        #expect(try await client.removeDataset(id: id.datasetID).wasPresent)
        #expect(await client.datasets().isEmpty)
    }
    @Test func dataInputHonorsConfiguredByteCap() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("data.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let client = try await SheepFenceClient.open(storeURL: url, configuration: .init(maximumLocationAge: 60,
            downloadPolicy: DownloadPolicy(maximumBytes: 1, timeout: 30)))
        await #expect(throws: GeofenceError.sourceFailed(.byteLimitExceeded(maximumBytes: 1))) {
            try await client.installSnapshot(data: Data([1, 2]))
        }
        #expect(await client.datasets().isEmpty)
    }
    @Test func failedOpenDoesNotLeakStoreLease() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([1]).write(to: directory)
        let url = directory.appendingPathComponent("data.sqlite")
        do { _ = try await SheepFenceClient.open(storeURL: url, configuration: .init(maximumLocationAge: 60)); Issue.record("open should fail") }
        catch { #expect(error as? GeofenceError != .storeAlreadyOpen) }
        try FileManager.default.removeItem(at: directory)
        let client = try await SheepFenceClient.open(storeURL: url, configuration: .init(maximumLocationAge: 60))
        #expect(await client.datasets().isEmpty)
    }
}
