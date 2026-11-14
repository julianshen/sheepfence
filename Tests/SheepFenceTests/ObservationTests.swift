import Foundation
import Testing
@testable import SheepFence

@Suite struct ObservationTests {
    let id = RegionID(datasetID: "d", featureID: "r")
    @Test func firstThenCrossingThenRepeat() {
        var state = ObservationState()
        let t = Date(timeIntervalSince1970: 100)
        let first = state.observe(id: id, revision: 1, timestamp: t, membership: .outside, distance: 20, radius: 5)
        #expect(first.event == .baseline(first.evaluation))
        let next = state.observe(id: id, revision: 1, timestamp: t.addingTimeInterval(1), membership: .inside, distance: 20, radius: 5)
        #expect(next.event == .entered(next.evaluation))
        #expect(state.observe(id: id, revision: 1, timestamp: t.addingTimeInterval(2), membership: .inside, distance: 20, radius: 5).event == nil)
    }
    @Test func equalityAndUncertaintyPreserveConfirmation() {
        var state = ObservationState()
        let t = Date(timeIntervalSince1970: 100)
        _ = state.observe(id: id, revision: 1, timestamp: t, membership: .inside, distance: 20, radius: 5)
        let uncertain = state.observe(id: id, revision: 2, timestamp: t.addingTimeInterval(1), membership: .outside, distance: 5, radius: 5)
        #expect(uncertain.event == nil)
        #expect(uncertain.evaluation.observation == .boundaryUncertain)
        #expect(uncertain.evaluation.lastConfirmed?.observedAt == t)
        #expect(uncertain.evaluation.lastConfirmed?.revision == 1)
    }
    @Test func uncertainFirstHasNoDefaultState() {
        var state = ObservationState()
        let result = state.observe(id: id, revision: 1, timestamp: Date(), membership: .inside, distance: 0, radius: 5)
        #expect(result.event == nil)
        #expect(result.evaluation.lastConfirmed == nil)
    }
    @Test func rebasingNeverEmitsMovement() {
        var state = ObservationState()
        _ = state.observe(id: id, revision: 1, timestamp: Date(), membership: .outside, distance: 20, radius: 5)
        state.remove(id)
        let result = state.observe(id: id, revision: 2, timestamp: Date(), membership: .inside, distance: 20, radius: 5, emitEvents: false)
        #expect(result.event == nil)
        #expect(result.evaluation.lastConfirmed?.membership == .inside)
        state.reset()
        let resumed = state.observe(id: id, revision: 2, timestamp: Date(), membership: .inside, distance: 20, radius: 5)
        #expect(resumed.event == .baseline(resumed.evaluation))
    }
}
