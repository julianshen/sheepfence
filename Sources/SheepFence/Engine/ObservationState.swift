import Foundation

struct ObservationState: Sendable {
    private(set) var confirmed: [RegionID: ConfirmedState] = [:]

    private var needsBaseline: Set<RegionID> = []
    mutating func reset() { confirmed.removeAll(); needsBaseline.removeAll() }
    mutating func interrupt() { needsBaseline.formUnion(confirmed.keys) }
    mutating func remove(_ id: RegionID) { confirmed.removeValue(forKey: id); needsBaseline.remove(id) }

    mutating func observe(id: RegionID, revision: Int, timestamp: Date,
                          membership: Membership, distance: Double, radius: Double,
                          emitEvents: Bool = true) -> (evaluation: RegionEvaluation, event: GeofenceEvent?) {
        let previous = confirmed[id]
        // Nonfinite distances cannot certify an observation. Equality is uncertain.
        guard distance.isFinite, radius.isFinite, distance > radius else {
            return (RegionEvaluation(regionID: id, revision: revision, observedAt: timestamp,
                                     observation: .boundaryUncertain, lastConfirmed: previous), nil)
        }
        let next = ConfirmedState(membership: membership, observedAt: timestamp, revision: revision)
        let requiresBaseline = needsBaseline.remove(id) != nil
        confirmed[id] = next
        let evaluation = RegionEvaluation(regionID: id, revision: revision, observedAt: timestamp,
                                          observation: .confirmed(membership), lastConfirmed: next)
        guard emitEvents else { return (evaluation, nil) }
        guard let previous, !requiresBaseline else { return (evaluation, .baseline(evaluation)) }
        guard previous.membership != membership else { return (evaluation, nil) }
        return (evaluation, membership == .inside ? .entered(evaluation) : .exited(evaluation))
    }

    func unavailable(id: RegionID, revision: Int, timestamp: Date,
                     reason: LocationUnavailableReason) -> RegionEvaluation {
        RegionEvaluation(regionID: id, revision: revision, observedAt: timestamp,
                         observation: .unavailable(reason), lastConfirmed: confirmed[id])
    }
}
