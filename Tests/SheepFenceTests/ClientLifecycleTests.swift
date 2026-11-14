import Foundation
import Testing
@testable import SheepFence

@MainActor final class FakeLocationProvider: LocationProvider {
    var onEvent: (@MainActor @Sendable (LocationProviderEvent) -> Void)?
    var starts = 0
    var stops = 0
    var settings: [SamplingSettings] = []
    func start() { starts += 1 }
    func stop() { stops += 1 }
    func apply(_ value: SamplingSettings) { settings.append(value) }
}
@Suite @MainActor struct ClientLifecycleTests {
    func make(empty: Bool = false, expected: Set<String> = []) throws -> (SheepFenceClient, FakeLocationProvider) {
        let fixture = EngineIntegrationTests()
        let snapshot = fixture.snapshot(1, empty: empty)
        let engine = GeofenceEngine(configuration: try GeofenceConfiguration(maximumLocationAge: 100, expectedDatasetIDs: expected), store: TestSnapshotStore(), source: UnusedSource(), decoder: { _ in snapshot }, geometry: GeometryOperations(contains: { _, _ in true }, distance: { _, _ in 100 }), snapshots: [snapshot])
        let provider = FakeLocationProvider()
        return (SheepFenceClient(engine: engine, provider: provider, sampling: { _, _ in SamplingSettings(distanceFilter: 5, desiredAccuracy: 10) }), provider)
    }
    @Test func reportsNoLocationAndProviderEvaluationFailure() async throws {
        let (client, provider) = try make(expected: ["missing"])
        var iterator = await client.events().makeAsyncIterator()
        try await client.startMonitoring(mode: .sdkManaged)
        #expect(await iterator.next() == .locationAvailabilityChanged(LocationAvailability(reason: .noLocation)))
        provider.onEvent?(.location(LocationSample(coordinate: Coordinate(longitude: 0, latitude: 0), timestamp: Date(), horizontalAccuracy: 5)))
        #expect(await iterator.next() == .evaluationFailed(.datasetNotReady("missing")))
        await client.stopMonitoring()
    }
    @Test func hostModeNeverStartsProvider() async throws {
        let (client, provider) = try make()
        try await client.startMonitoring(mode: .hostProvided)
        try await client.startMonitoring(mode: .hostProvided)
        #expect(provider.starts == 0)
        await #expect(throws: GeofenceError.sourceModeConflict) { try await client.startMonitoring(mode: .sdkManaged) }
        await client.stopMonitoring()
    }
    @Test func sdkModeIsIdempotentAndStopClearsCallback() async throws {
        let (client, provider) = try make()
        try await client.startMonitoring(mode: .sdkManaged)
        try await client.startMonitoring(mode: .sdkManaged)
        #expect(provider.starts == 1)
        #expect(provider.onEvent != nil)
        await client.stopMonitoring()
        #expect(provider.onEvent == nil)
        try await client.startMonitoring(mode: .sdkManaged)
        #expect(provider.starts == 2)
        await client.stopMonitoring()
    }
    @Test func emptyDatasetDoesNotAcquireLocation() async throws {
        let (client, provider) = try make(empty: true)
        try await client.startMonitoring(mode: .sdkManaged)
        #expect(provider.starts == 0)
        await client.stopMonitoring()
    }
    @Test func overlappingStartStopSerializes() async throws {
        let (client, provider) = try make()
        let start = Task { try await client.startMonitoring(mode: .sdkManaged) }
        let stop = Task { await client.stopMonitoring() }
        try await start.value
        await stop.value
        // Explicit stop after both also proves repeated stop is safe.
        await client.stopMonitoring()
        #expect(provider.onEvent == nil)
    }
}
