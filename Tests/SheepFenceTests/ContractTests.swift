import Foundation
import Testing
@testable import SheepFence

@Suite struct ContractTests {
    @Test func sourceModeIsExclusiveAndIdempotent() throws {
        var session = MonitoringSession()
        #expect(try session.start(.hostProvided))
        let firstGeneration = session.generation
        #expect(try !session.start(.hostProvided))
        #expect(session.generation == firstGeneration)
        #expect(throws: GeofenceError.sourceModeConflict) { try session.start(.sdkManaged) }
        let stopped = session.stop()
        let stoppedAgain = session.stop()
        #expect(stopped)
        #expect(!stoppedAgain)
        #expect(try session.start(.sdkManaged))
        #expect(throws: GeofenceError.sourceModeConflict) { try session.requireHostSource() }
    }
    @Test func readyEmptyDatasetDiffersFromMissing() throws {
        // Readiness depends on installed datasets, not the number of regions.
        try DatasetReadinessCheck.check(installed: ["empty"], expected: ["empty"])
        #expect(throws: GeofenceError.datasetNotReady("missing")) {
            try DatasetReadinessCheck.check(installed: ["empty"], expected: ["missing"])
        }
        #expect(throws: GeofenceError.datasetNotReady(nil)) {
            try DatasetReadinessCheck.check(installed: [], expected: [])
        }
    }
    @Test func reducedAccuracyIsNotUnavailability() {
        let available = LocationAvailability(reducedAccuracy: true)
        #expect(available.reason == nil)
        #expect(available.reducedAccuracy)
        #expect(LocationAvailability(reason: .authorizationDenied).reason == .authorizationDenied)
    }
    @Test func queryBindsRevisionToMembership() {
        let result = GeometryQueryResult(regionID: RegionID(datasetID: "d", featureID: "r"), revision: 4, membership: .inside)
        #expect(result.revision == 4)
        #expect(result.membership == .inside)
    }
    @Test func explicitSampleIsSendable() {
        let sample = LocationSample(coordinate: Coordinate(longitude: 10, latitude: 20), timestamp: Date(), horizontalAccuracy: 5)
        #expect(sample.horizontalAccuracy == 5)
    }
    @Test func downloadLimitsAreRequiredAndValidated() throws {
        #expect(throws: GeofenceError.self) { try DownloadPolicy(maximumBytes: 0, timeout: 5) }
        #expect(throws: GeofenceError.self) { try DownloadPolicy(maximumBytes: 100, timeout: .infinity) }
        let policy = try DownloadPolicy(maximumBytes: 1000, timeout: 10)
        #expect(policy.maximumBytes == 1000)
    }
}

// Compile-time integration surface check, not a fake engine behavior test.
private func checkClientSurface<C: GeofenceClient>(_ client: C, coordinate: Coordinate, region: RegionID) async throws {
    let _: Bool = try await client.contains(coordinate: coordinate, in: region)
    let _: GeometryQueryResult = try await client.query(coordinate: coordinate, in: region)
    try await client.startMonitoring(mode: .hostProvided)
    try await client.updateAvailability(LocationAvailability(reason: .servicesDisabled))
    await client.stopMonitoring()
}
