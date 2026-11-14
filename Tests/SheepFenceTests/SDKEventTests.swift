import Foundation
import Testing
@testable import SheepFence

private final class AdvancingClock: GeofenceClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ seconds: Double) { value = Date(timeIntervalSince1970: seconds) }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ seconds: Double) { lock.lock(); value = Date(timeIntervalSince1970: seconds); lock.unlock() }
}
struct SDKEventTests {
    @Test func freshnessGapResetsWithoutReadingState() async throws {
        let h = EngineIntegrationTests(), snapshot = EngineIntegrationTests().snapshot(1)
        let clock = AdvancingClock(1000)
        let engine = GeofenceEngine(configuration: try .init(maximumLocationAge: 60),
            store: TestSnapshotStore(), source: UnusedSource(), decoder: { _ in snapshot },
            geometry: .init(contains: { p, _ in p.longitude > 0 }, distance: { _, _ in 100 }),
            clock: clock, snapshots: [snapshot])
        try await engine.startMonitoring(mode: .hostProvided)
        _ = try await engine.submit(location: h.sample(-1, 999))
        let stream = try await engine.eventStream()
        var iterator = stream.makeAsyncIterator()
        _ = try await iterator.next()
        clock.set(1100)
        let recovered = try await engine.submit(location: h.sample(1, 1099))
        #expect(try await iterator.next() == .baseline(recovered.results[0]))
        #expect(try await iterator.next() == .evaluated(recovered))
        clock.set(1200)
        let stale = await engine.currentState()
        #expect(stale.evaluations.first?.observation == .unavailable(.staleLocation))
        #expect(stale.evaluations.first?.lastConfirmed?.membership == .inside)
    }

    @Test func pureEvaluationNeverSeedsMonitoringHistory() async throws {
        let helper = EngineIntegrationTests()
        let snapshot = helper.snapshot(1)
        let engine = try helper.engine([snapshot])
        _ = try await engine.install(data: snapshot.sourceBytes)
        try await engine.startMonitoring(mode: .hostProvided)
        let stream = try await engine.eventStream()
        var iterator = stream.makeAsyncIterator()
        _ = try await iterator.next() // atomic initial state
        let pure = try await engine.evaluateOnce(location: helper.sample(-1))
        #expect(pure.results[0].lastConfirmed == nil)
        let value = try await engine.submit(location: helper.sample(1, 901))
        #expect(try await iterator.next() == .locationAvailabilityChanged(LocationAvailability()))
        #expect(try await iterator.next() == .baseline(value.results[0]))
        #expect(try await iterator.next() == .evaluated(value))
    }
    @Test func overflowFailsOnlySlowSubscriber() async throws {
        let helper = EngineIntegrationTests()
        let engine = try helper.engine([helper.snapshot(1)])
        let slow = try await engine.eventStream(bufferCapacity: 1)
        let fast = try await engine.eventStream(bufferCapacity: 8)
        try await engine.startMonitoring(mode: .hostProvided)
        var slowIterator = slow.makeAsyncIterator()
        _ = try await slowIterator.next()
        await #expect(throws: GeofenceError.eventBufferOverflow) { _ = try await slowIterator.next() }
        var fastIterator = fast.makeAsyncIterator()
        guard case .stateSnapshot? = try await fastIterator.next() else { Issue.record("initial snapshot missing"); return }
        guard case .locationAvailabilityChanged? = try await fastIterator.next() else { Issue.record("start availability missing"); return }
        guard case .stateSnapshot(let state)? = try await fastIterator.next() else { Issue.record("start state missing"); return }
        #expect(state.mode == .hostProvided)
    }
    @Test func gpsLossRetainsHistoryButRecoveryIsBaseline() async throws {
        let helper = EngineIntegrationTests(), snapshot = EngineIntegrationTests().snapshot(1)
        let engine = try helper.engine([snapshot])
        _ = try await engine.install(data: snapshot.sourceBytes)
        try await engine.startMonitoring(mode: .hostProvided)
        let first = try await engine.submit(location: helper.sample(-1))
        try await engine.updateAvailability(.init(reason: .noLocation))
        let unavailable = await engine.currentState()
        #expect(unavailable.evaluations.first?.observation == .unavailable(.noLocation))
        #expect(unavailable.evaluations.first?.lastConfirmed == first.results.first?.lastConfirmed)
        let pure = try await engine.evaluateOnce(location: helper.sample(1, 901))
        #expect(pure.results.first?.observation == .confirmed(.inside))
        try await engine.updateAvailability(.init())
        let stream = try await engine.eventStream()
        var iterator = stream.makeAsyncIterator()
        _ = try await iterator.next()
        let recovery = try await engine.submit(location: helper.sample(1, 902))
        _ = try await iterator.next() // availability acquired
        #expect(try await iterator.next() == .baseline(recovery.results[0]))
    }
    @Test func firstRejectedSampleIsVisibleInCurrentState() async throws {
        let h = EngineIntegrationTests(), snapshot = EngineIntegrationTests().snapshot(1)
        let engine = try h.engine([snapshot])
        _ = try await engine.install(data: snapshot.sourceBytes)
        try await engine.startMonitoring(mode: .hostProvided)
        _ = try await engine.submit(location: h.sample(1, 900, accuracy: -1))
        #expect(await engine.currentState().evaluations.first?.observation == .unavailable(.invalidAccuracy))
    }
    @Test func submitRequiresActiveHostMode() async throws {
        let helper = EngineIntegrationTests(), engine = try EngineIntegrationTests().engine([])
        await #expect(throws: GeofenceError.monitoringNotStarted) { try await engine.submit(location: helper.sample(1)) }
        try await engine.startMonitoring(mode: .sdkManaged)
        await #expect(throws: GeofenceError.sourceModeConflict) { try await engine.submit(location: helper.sample(1)) }
        await #expect(throws: GeofenceError.invalidConfiguration("Event capacity must be positive")) {
            try await engine.eventStream(bufferCapacity: 0)
        }
    }
}
