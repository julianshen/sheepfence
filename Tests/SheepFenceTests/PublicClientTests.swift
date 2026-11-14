import Foundation
import Testing
import SheepFence

@Suite @MainActor struct PublicClientTests {
    @Test func publicConstructionInstallsAndRestoresOffline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("snapshot.sqlite")
        let configuration = try GeofenceConfiguration(maximumLocationAge: 60)
        let downloads = try DownloadPolicy(maximumBytes: 1_000_000, timeout: 30)
        let sampling = try SamplingPolicyConfiguration()
        var client: SheepFenceClient? = try await .open(storeURL: storeURL, configuration: configuration,
            downloadPolicy: downloads, samplingConfiguration: sampling)
        let fixture = try #require(Bundle.module.url(forResource: "campus-v3", withExtension: "geojson"))
        _ = try await client!.installSnapshot(from: fixture)
        let region = RegionID(datasetID: "com.example.campus", featureID: "garden")
        let coordinate = Coordinate(longitude: 10.003, latitude: 20.002)
        #expect(try await client!.query(coordinate: coordinate, in: region).membership == .inside)
        await client!.stopMonitoring()
        client = nil
        let reopened = try await SheepFenceClient.open(storeURL: storeURL, configuration: configuration,
            downloadPolicy: downloads, samplingConfiguration: sampling)
        #expect(try await reopened.query(coordinate: coordinate, in: region).revision == 3)
        let observations = try await reopened.evaluate(location: LocationSample(coordinate: coordinate,
            timestamp: Date(), horizontalAccuracy: 1))
        #expect(observations.contains { $0.regionID == region && $0.observation == .confirmed(.inside) })
        await reopened.stopMonitoring()
    }
}
