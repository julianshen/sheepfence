import Foundation

struct GeometryOperations: Sendable {
    let contains: @Sendable (Coordinate, RegionGeometry) -> Bool
    let distance: @Sendable (Coordinate, RegionGeometry) -> Double
    let candidate: @Sendable (Coordinate, Double, [RegionBounds]) -> Bool
    init(contains: @escaping @Sendable (Coordinate, RegionGeometry) -> Bool,
         distance: @escaping @Sendable (Coordinate, RegionGeometry) -> Double,
         candidate: @escaping @Sendable (Coordinate, Double, [RegionBounds]) -> Bool = { _, _, _ in true }) {
        self.contains = contains; self.distance = distance; self.candidate = candidate
    }
}

/// The serialization point for query snapshots, observation state and emitted events.
actor GeofenceEngine: GeofenceClient {
    private let configuration: GeofenceConfiguration
    private let store: any SnapshotStore
    private let source: any SnapshotSource
    private let decoder: @Sendable (Data) throws -> ValidatedSnapshot
    private let geometry: GeometryOperations
    private let clock: any GeofenceClock
    private var snapshots: [String: ValidatedSnapshot]
    private var state = ObservationState()
    private var session = MonitoringSession()
    private var availability = LocationAvailability()
    private var recentSample: LocationSample?
    private var lastTimestamp: Date?
    private var subscribers: [UUID: AsyncStream<GeofenceEvent>.Continuation] = [:]
    // A queue of complete commit+publication operations prevents actor reentrancy from
    // reversing publication order while the store is saving on its private queue.
    private var installTail: Task<Void, Never>?

    init(configuration: GeofenceConfiguration, store: any SnapshotStore, source: any SnapshotSource,
         decoder: @escaping @Sendable (Data) throws -> ValidatedSnapshot,
         geometry: GeometryOperations, clock: any GeofenceClock = SystemGeofenceClock(),
         snapshots: [ValidatedSnapshot] = []) {
        self.configuration = configuration; self.store = store; self.source = source
        self.decoder = decoder; self.geometry = geometry; self.clock = clock
        self.snapshots = Dictionary(snapshots.map { ($0.metadata.id, $0) }, uniquingKeysWith: { a, b in
            a.metadata.revision >= b.metadata.revision ? a : b
        })
    }

    func events() -> AsyncStream<GeofenceEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<GeofenceEvent>.makeStream(bufferingPolicy: .unbounded)
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.removeSubscriber(id) } }
        return stream
    }
    private func removeSubscriber(_ id: UUID) { subscribers.removeValue(forKey: id) }
    private func emit(_ event: GeofenceEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }
    deinit { for continuation in subscribers.values { continuation.finish() } }

    func installSnapshot(from url: URL) async throws -> InstallResult {
        let data = try await source.read(from: url)
        try Task.checkCancellation()
        return try await install(data: data)
    }
    func install(data: Data) async throws -> InstallResult {
        let decode = decoder
        let candidate = try await Task.detached { try decode(data) }.value
        try Task.checkCancellation()
        let previous = installTail
        let work = Task { [self] in
            await previous?.value
            // Once queued, a transaction runs to completion; publication must follow a
            // successful durable save even if the original caller stops waiting.
            return try await persistAndPublish(candidate)
        }
        installTail = Task { _ = try? await work.value }
        return try await work.value
    }
    private func persistAndPublish(_ candidate: ValidatedSnapshot) async throws -> InstallResult {
        let commit = try await store.commit(candidate)
        guard commit.result.outcome == .installed else { return commit.result }
        let next = commit.effectiveSnapshot
        let old = snapshots[next.metadata.id]
        // Protect against any future store implementation that returns a superseded commit.
        if let old, old.metadata.revision >= next.metadata.revision { return commit.result }
        snapshots[next.metadata.id] = next
        let oldByID = Dictionary((old?.regions ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        let nextByID = Dictionary(next.regions.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        let removed = (old?.regions ?? []).filter { $0.enabled && nextByID[$0.id]?.enabled != true }.map(\.id)
        for id in removed { state.remove(id) }
        let affected = next.regions.filter { region in
            guard region.enabled else { return false }
            guard let previous = oldByID[region.id], previous.enabled else { return true }
            return previous.geometry != region.geometry
        }.sorted(by: regionOrder)
        for region in affected { state.remove(region.id) }
        var evaluations: [RegionEvaluation] = []
        if let sample = recentSample, invalidReason(sample) == nil, availability.reason == nil {
            for region in affected {
                evaluations.append(observe(sample, region: region, revision: next.metadata.revision, emitEvents: false))
            }
        }
        emit(.datasetChanged(DatasetChange(dataset: next.metadata, affectedRegionIDs: affected.map(\.id),
                                           removedRegionIDs: removed.sorted(by: idOrder), evaluations: evaluations)))
        return commit.result
    }
    func query(coordinate: Coordinate, in id: RegionID) throws -> GeometryQueryResult {
        guard coordinate.isValid else { throw GeofenceError.invalidCoordinate }
        guard let dataset = snapshots[id.datasetID] else { throw GeofenceError.datasetNotReady(id.datasetID) }
        guard let region = dataset.regions.first(where: { $0.id == id }) else { throw GeofenceError.regionNotFound(id) }
        return GeometryQueryResult(regionID: id, revision: dataset.metadata.revision,
                                   membership: geometry.contains(coordinate, region.geometry) ? .inside : .outside)
    }
    func evaluate(location: LocationSample) throws -> [RegionEvaluation] {
        try session.requireHostSource()
        return try evaluateAcceptedSource(location)
    }
    func receive(_ sample: LocationSample, generation: UInt64) throws -> [RegionEvaluation] {
        guard session.mode == .sdkManaged, session.generation == generation else { return [] }
        return try evaluateAcceptedSource(sample)
    }
    private func evaluateAcceptedSource(_ sample: LocationSample) throws -> [RegionEvaluation] {
        try DatasetReadiness.check(installed: Set(snapshots.keys), expected: configuration.expectedDatasetIDs)
        let regions = enabledRegions()
        if let reason = availability.reason ?? invalidReason(sample) {
            return regions.map { state.unavailable(id: $0.region.id, revision: $0.revision,
                                                   timestamp: sample.timestamp, reason: reason) }
        }
        if let lastTimestamp, sample.timestamp <= lastTimestamp {
            return regions.map { state.unavailable(id: $0.region.id, revision: $0.revision,
                                                   timestamp: sample.timestamp, reason: .outOfOrderLocation) }
        }
        if recentSample == nil, session.mode != nil {
            emit(.locationAvailabilityChanged(availability))
        }
        lastTimestamp = sample.timestamp
        recentSample = sample
        return regions.map { observe(sample, region: $0.region, revision: $0.revision) }
    }
    private func observe(_ sample: LocationSample, region: Region, revision: Int, emitEvents: Bool = true) -> RegionEvaluation {
        let radius = sample.horizontalAccuracy + configuration.boundaryBufferMeters
        let candidate = geometry.candidate(sample.coordinate, radius, region.bounds)
        // A conservative expanded-bounds rejection proves certain outside. Still run
        // the state transition, including prior-inside regions, so exits cannot vanish.
        let result = state.observe(id: region.id, revision: revision, timestamp: sample.timestamp,
                                   membership: candidate && geometry.contains(sample.coordinate, region.geometry) ? .inside : .outside,
                                   distance: candidate ? geometry.distance(sample.coordinate, region.geometry) : 1,
                                   radius: candidate ? radius : 0,
                                   emitEvents: emitEvents)
        if let event = result.event { emit(event) }
        return result.evaluation
    }
    private func invalidReason(_ sample: LocationSample) -> LocationUnavailableReason? {
        guard sample.coordinate.isValid else { return .invalidCoordinate }
        guard sample.horizontalAccuracy.isFinite, sample.horizontalAccuracy >= 0 else { return .invalidAccuracy }
        let age = clock.now().timeIntervalSince(sample.timestamp)
        guard age.isFinite else { return .staleLocation }
        if age < -configuration.maximumFutureSkew { return .futureLocation }
        if age > configuration.maximumLocationAge { return .staleLocation }
        return nil
    }
    func startMonitoring(mode: LocationSourceMode) throws {
        if try session.start(mode) {
            resetObservations()
            emit(.locationAvailabilityChanged(LocationAvailability(reason: availability.reason ?? .noLocation,
                                                                     reducedAccuracy: availability.reducedAccuracy)))
        }
    }
    func reportEvaluationFailure(_ error: GeofenceError, generation: UInt64) {
        guard session.mode == .sdkManaged, session.generation == generation else { return }
        emit(.evaluationFailed(error))
    }
    func stopMonitoring() {
        if session.stop() {
            resetObservations()
            emit(.locationAvailabilityChanged(LocationAvailability(reason: .monitoringStopped)))
        }
    }
    func updateAvailability(_ value: LocationAvailability) throws {
        try session.requireHostSource()
        applyAvailability(value)
    }
    func receiveAvailability(_ value: LocationAvailability, generation: UInt64) {
        guard session.mode == .sdkManaged, session.generation == generation else { return }
        applyAvailability(value)
    }
    private func applyAvailability(_ value: LocationAvailability) {
        guard availability != value else { return }
        availability = value
        if value.reason != nil { resetObservations() }
        emit(.locationAvailabilityChanged(value))
    }
    private func resetObservations() { state.reset(); recentSample = nil; lastTimestamp = nil }
    func monitoringGeneration() -> UInt64 { session.generation }
    func hasEnabledRegions() -> Bool { snapshots.values.contains { $0.regions.contains(where: \.enabled) } }
    func nearestBoundary(to sample: LocationSample) -> Double? {
        enabledRegions().map { geometry.distance(sample.coordinate, $0.region.geometry) }.min()
    }
    private func enabledRegions() -> [(region: Region, revision: Int)] {
        snapshots.values.flatMap { snapshot in
            snapshot.regions.filter(\.enabled).map { (region: $0, revision: snapshot.metadata.revision) }
        }.sorted { regionOrder($0.region, $1.region) }
    }
}

private func idOrder(_ a: RegionID, _ b: RegionID) -> Bool {
    a.featureID == b.featureID ? a.datasetID < b.datasetID : a.featureID < b.featureID
}
private func regionOrder(_ a: Region, _ b: Region) -> Bool {
    a.priority == b.priority ? idOrder(a.id, b.id) : a.priority > b.priority
}
