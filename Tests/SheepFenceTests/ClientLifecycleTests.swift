import Foundation
import Testing
@testable import SheepFence

@MainActor final class FakeLocationProvider: LocationProvider {
    var onEvent: (@MainActor @Sendable (LocationProviderEvent) -> Void)?
    var starts = 0
    var stops = 0
    var settings: [SamplingSettings] = []
    var settingsAtStart: [SamplingSettings?] = []
    func start() { starts += 1; settingsAtStart.append(settings.last) }
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
        var iterator = try await client.events().makeAsyncIterator()
        _ = try await iterator.next() // initial stopped snapshot
        try await client.startMonitoring(mode: .sdkManaged)
        #expect(try await iterator.next() == .locationAvailabilityChanged(LocationAvailability(reason: .noLocation)))
        _ = try await iterator.next() // start state snapshot
        provider.onEvent?(.location(LocationSample(coordinate: Coordinate(longitude: 0, latitude: 0), timestamp: Date(), horizontalAccuracy: 5)))
        #expect(try await iterator.next() == .evaluationFailed(.datasetNotReady("missing")))
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
    @Test func initialSamplingIsAppliedBeforeEveryProviderStart() async throws {
        let snapshot = EngineIntegrationTests().snapshot(1)
        let engine = GeofenceEngine(configuration: try GeofenceConfiguration(maximumLocationAge: 100),
            store: TestSnapshotStore(), source: UnusedSource(), decoder: { _ in snapshot },
            geometry: GeometryOperations(contains: { _, _ in true }, distance: { _, _ in 100 }), snapshots: [snapshot])
        let provider = FakeLocationProvider()
        var resets = 0
        let initial = SamplingSettings(distanceFilter: 1, desiredAccuracy: 2)
        let client = SheepFenceClient(engine: engine, provider: provider,
            sampling: { _, _ in SamplingSettings(distanceFilter: 50, desiredAccuracy: 100) },
            resetSampling: { resets += 1; return initial })
        try await client.startMonitoring(mode: .sdkManaged)
        try await client.startMonitoring(mode: .sdkManaged)
        await client.stopMonitoring()
        try await client.startMonitoring(mode: .sdkManaged)
        #expect(resets == 2)
        #expect(provider.settingsAtStart == [initial, initial])
        await client.stopMonitoring()
    }
}
