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
actor GeofenceEngine {
    private let configuration: GeofenceConfiguration
    private let store: any SnapshotStore
    private let storeLease: StoreLease?
    private let source: any SnapshotSource
    private let decoder: @Sendable (Data) throws -> ValidatedSnapshot
    private let geometry: GeometryOperations
    private let clock: any GeofenceClock
    private let onTransactionQueued: @Sendable () -> Void
    private var snapshots: [String: ValidatedSnapshot]
    private var state = ObservationState()
    private var session = MonitoringSession()
    private var availability = LocationAvailability()
    private var recentSample: LocationSample?
    private var lastTimestamp: Date?
    // A queue of complete commit+publication operations prevents actor reentrancy from
    // reversing publication order while the store is saving on its private queue.
    private var latest: [RegionID: RegionEvaluation] = [:]
    private var streamSubscribers: [UUID: AsyncThrowingStream<GeofenceEvent, Error>.Continuation] = [:]
    private var installTail: Task<Void, Never>?

    init(configuration: GeofenceConfiguration, store: any SnapshotStore, source: any SnapshotSource,
         decoder: @escaping @Sendable (Data) throws -> ValidatedSnapshot,
         geometry: GeometryOperations, clock: any GeofenceClock = SystemGeofenceClock(),
         snapshots: [ValidatedSnapshot] = [], storeLease: StoreLease? = nil,
         onTransactionQueued: @escaping @Sendable () -> Void = {}) {
        self.configuration = configuration; self.store = store; self.storeLease = storeLease; self.source = source
        self.decoder = decoder; self.geometry = geometry; self.clock = clock
        self.onTransactionQueued = onTransactionQueued
        self.snapshots = Dictionary(snapshots.map { ($0.metadata.id, $0) }, uniquingKeysWith: { a, b in
            a.metadata.revision >= b.metadata.revision ? a : b
        })
    }

    private func emit(_ event: GeofenceEvent) {
        for (id, continuation) in streamSubscribers {
            switch continuation.yield(event) {
            case .dropped:
                continuation.finish(throwing: GeofenceError.eventBufferOverflow)
                streamSubscribers.removeValue(forKey: id)
            case .terminated: streamSubscribers.removeValue(forKey: id)
            case .enqueued: break
            @unknown default: break
            }
        }
    }
    deinit {
        for continuation in streamSubscribers.values { continuation.finish() }
    }
    func eventStream(bufferCapacity: Int = 256) throws -> AsyncThrowingStream<GeofenceEvent, Error> {
        guard bufferCapacity > 0 else { throw GeofenceError.invalidConfiguration("Event capacity must be positive") }
        let id = UUID()
        let (stream, continuation) = AsyncThrowingStream<GeofenceEvent, Error>.makeStream(bufferingPolicy: .bufferingOldest(bufferCapacity))
        streamSubscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.removeStreamSubscriber(id) } }
        continuation.yield(.stateSnapshot(currentState()))
        return stream
    }
    private func removeStreamSubscriber(_ id: UUID) { streamSubscribers.removeValue(forKey: id) }
    func datasets() -> [DatasetSummary] {
        snapshots.values.sorted { $0.metadata.id < $1.metadata.id }.map {
            DatasetSummary(metadata: $0.metadata, regionCount: $0.regions.count,
                           enabledRegionCount: $0.regions.filter(\.enabled).count)
        }
    }
    func regions(in datasetID: String? = nil) throws -> [RegionSummary] {
        if let datasetID, snapshots[datasetID] == nil { throw GeofenceError.datasetNotReady(datasetID) }
        return snapshots.values.filter { datasetID == nil || $0.metadata.id == datasetID }
            .flatMap { snapshot in snapshot.regions.map { region in
                RegionSummary(id: region.id, revision: snapshot.metadata.revision, name: region.name,
                              enabled: region.enabled, priority: region.priority)
            }}.sorted {
                $0.priority == $1.priority ? idOrder($0.id, $1.id) : $0.priority > $1.priority
            }
    }
    func currentState() -> MonitoringState {
        let missing = configuration.expectedDatasetIDs.subtracting(snapshots.keys)
        let readiness: DatasetReadiness = !missing.isEmpty ? .missingRequired(missing) : snapshots.isEmpty ? .noDatasets : .ready
        var reason = availability.reason
        if session.mode == nil { reason = .monitoringStopped }
        else if reason == nil {
            if let sample = recentSample { reason = invalidReason(sample) }
            else if let value = latest.values.first, case .unavailable(let rejected) = value.observation {
                reason = rejected
            } else { reason = .noLocation }
        }
        let evaluations: [RegionEvaluation] = session.mode == nil || readiness != .ready ? [] : enabledRegions().map { item in
            if let reason {
                return state.unavailable(id: item.region.id, revision: item.revision,
                                         timestamp: recentSample?.timestamp ?? clock.now(), reason: reason)
            }
            if let value = latest[item.region.id], value.revision == item.revision { return value }
            return state.unavailable(id: item.region.id, revision: item.revision,
                                     timestamp: clock.now(), reason: .noLocation)
        }
        return MonitoringState(mode: session.mode, readiness: readiness,
            availability: LocationAvailability(reason: reason, reducedAccuracy: availability.reducedAccuracy),
            datasets: datasets(), evaluations: evaluations)
    }
    private func batch(_ sample: LocationSample, _ results: [RegionEvaluation]) -> EvaluationBatch {
        EvaluationBatch(evaluatedAt: clock.now(), sampleTimestamp: sample.timestamp,
                        datasets: datasets().map(\.metadata), results: results)
    }
    func distance(from coordinate: Coordinate, to id: RegionID) throws -> RegionDistanceResult {
        guard coordinate.isValid else { throw GeofenceError.invalidCoordinate }
        guard let snapshot = snapshots[id.datasetID] else { throw GeofenceError.datasetNotReady(id.datasetID) }
        guard let region = snapshot.regions.first(where: { $0.id == id }) else { throw GeofenceError.regionNotFound(id) }
        return try RegionDistanceResult(regionID: id, revision: snapshot.metadata.revision,
            membership: geometry.contains(coordinate, region.geometry) ? .inside : .outside,
            boundaryDistance: Geometry.boundaryDistanceEstimate(coordinate, in: region.geometry))
    }
    func evaluateOnce(location sample: LocationSample) throws -> EvaluationBatch {
        try DatasetReadinessCheck.check(installed: Set(snapshots.keys), expected: configuration.expectedDatasetIDs)
        let invalid = invalidReason(sample)
        let results = enabledRegions().map { item in
            let observation: Observation
            if let invalid { observation = .unavailable(invalid) }
            else {
                let radius = sample.horizontalAccuracy + configuration.boundaryBufferMeters
                let candidate = geometry.candidate(sample.coordinate, radius, item.region.bounds)
                let distance = candidate ? geometry.distance(sample.coordinate, item.region.geometry) : .infinity
                if candidate && (!distance.isFinite || !radius.isFinite || distance <= radius) {
                    observation = .boundaryUncertain
                } else {
                    observation = .confirmed(candidate && geometry.contains(sample.coordinate, item.region.geometry) ? .inside : .outside)
                }
            }
            return RegionEvaluation(regionID: item.region.id, revision: item.revision, observedAt: sample.timestamp,
                                    observation: observation, lastConfirmed: nil)
        }
        return batch(sample, results)
    }
    func submit(location sample: LocationSample) throws -> EvaluationBatch {
        try session.requireActiveHostSource()
        return batch(sample, try evaluateAcceptedSource(sample))
    }

    func installSnapshot(from url: URL) async throws -> InstallResult {
        let data = try await source.read(from: url)
        try Task.checkCancellation()
        return try await install(data: data)
    }
    func install(data: Data) async throws -> InstallResult {
        guard data.count <= configuration.downloadPolicy.maximumBytes else {
            throw GeofenceError.sourceFailed(.byteLimitExceeded(maximumBytes: configuration.downloadPolicy.maximumBytes))
        }
        try Task.checkCancellation()
        let decode = decoder
        let candidate = try await Task.detached { try decode(data) }.value
        try Task.checkCancellation()
        let previous = installTail
        let gate = CommitGate()
        let work = Task { [self] in
            await previous?.value
            try gate.begin()
            // After this point the durable outcome must be published even on cancellation.
            return try await persistAndPublish(candidate)
        }
        installTail = Task { _ = try? await work.value }
        onTransactionQueued()
        return try await withTaskCancellationHandler { try await work.value } onCancel: { gate.cancel() }
    }
    func removeDataset(id: String) async throws -> DatasetRemovalResult {
        try Task.checkCancellation()
        let previous = installTail
        let gate = CommitGate()
        let work = Task { [self] in
            await previous?.value
            try gate.begin()
            let result: DatasetRemovalResult
            do { result = try await store.removeDataset(id: id) }
            catch { throw Self.storageError(error) }
            if result.wasPresent {
                let removed = snapshots.removeValue(forKey: id)
                for region in removed?.regions ?? [] { state.remove(region.id); latest.removeValue(forKey: region.id) }
                emit(.datasetRemoved(result))
            }
            return result
        }
        installTail = Task { _ = try? await work.value }
        onTransactionQueued()
        return try await withTaskCancellationHandler { try await work.value } onCancel: { gate.cancel() }
    }
    private static func storageError(_ error: Error) -> Error {
        if error is CancellationError || error is GeofenceError { return error }
        return GeofenceError.storageFailed("Persistence operation failed")
    }
    private func persistAndPublish(_ candidate: ValidatedSnapshot) async throws -> InstallResult {
        let commit: SnapshotCommit
        do { commit = try await store.commit(candidate) }
        catch { throw Self.storageError(error) }
        guard commit.result.outcome == .installed else { return commit.result }
        let next = commit.effectiveSnapshot
        let old = snapshots[next.metadata.id]
        // Protect against any future store implementation that returns a superseded commit.
        if let old, old.metadata.revision >= next.metadata.revision { return commit.result }
        snapshots[next.metadata.id] = next
        let oldByID = Dictionary((old?.regions ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        let nextByID = Dictionary(next.regions.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        let removed = (old?.regions ?? []).filter { $0.enabled && nextByID[$0.id]?.enabled != true }.map(\.id)
        for id in removed { state.remove(id); latest.removeValue(forKey: id) }
        let affected = next.regions.filter { region in
            guard region.enabled else { return false }
            guard let previous = oldByID[region.id], previous.enabled else { return true }
            return previous.geometry != region.geometry
        }.sorted(by: regionOrder)
        for region in affected { state.remove(region.id); latest.removeValue(forKey: region.id) }
        var evaluations: [RegionEvaluation] = []
        if let sample = recentSample, invalidReason(sample) == nil, availability.reason == nil {
            for region in affected {
                evaluations.append(observe(sample, region: region, revision: next.metadata.revision, emitEvents: false))
            }
        }
        if let sample = recentSample, invalidReason(sample) == nil, availability.reason == nil {
            for region in next.regions where region.enabled {
                latest[region.id] = observe(sample, region: region, revision: next.metadata.revision, emitEvents: false)
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
    func receive(_ sample: LocationSample, generation: UInt64) throws -> [RegionEvaluation] {
        guard session.mode == .sdkManaged, session.generation == generation else { return [] }
        return try evaluateAcceptedSource(sample)
    }
    private func evaluateAcceptedSource(_ sample: LocationSample) throws -> [RegionEvaluation] {
        try DatasetReadinessCheck.check(installed: Set(snapshots.keys), expected: configuration.expectedDatasetIDs)
        let regions = enabledRegions()
        var reason = availability.reason ?? invalidReason(sample)
        if reason == nil, let lastTimestamp, sample.timestamp <= lastTimestamp { reason = .outOfOrderLocation }
        let results: [RegionEvaluation]
        if let reason {
            results = regions.map { state.unavailable(id: $0.region.id, revision: $0.revision,
                                                       timestamp: sample.timestamp, reason: reason) }
        } else {
            if let prior = recentSample, sample.timestamp.timeIntervalSince(prior.timestamp) > configuration.maximumLocationAge {
                state.interrupt()
            }
            if recentSample == nil, session.mode != nil { emit(.locationAvailabilityChanged(availability)) }
            lastTimestamp = sample.timestamp
            recentSample = sample
            results = regions.map { observe(sample, region: $0.region, revision: $0.revision) }
        }
        latest = Dictionary(uniqueKeysWithValues: results.map { ($0.regionID, $0) })
        emit(.evaluated(batch(sample, results)))
        return results
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
            emit(.stateSnapshot(currentState()))
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
            emit(.stateSnapshot(currentState()))
        }
    }
    func updateAvailability(_ value: LocationAvailability) throws {
        try session.requireActiveHostSource()
        applyAvailability(value)
    }
    func receiveAvailability(_ value: LocationAvailability, generation: UInt64) {
        guard session.mode == .sdkManaged, session.generation == generation else { return }
        applyAvailability(value)
    }
    private func applyAvailability(_ value: LocationAvailability) {
        guard availability != value else { return }
        availability = value
        if value.reason != nil { state.interrupt(); recentSample = nil; lastTimestamp = nil }
        emit(.locationAvailabilityChanged(value))
        emit(.stateSnapshot(currentState()))
    }
    private func resetObservations() { state.reset(); latest.removeAll(); recentSample = nil; lastTimestamp = nil; availability = LocationAvailability() }
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
    a.datasetID == b.datasetID ? a.featureID < b.featureID : a.datasetID < b.datasetID
}
private func regionOrder(_ a: Region, _ b: Region) -> Bool {
    a.priority == b.priority ? idOrder(a.id, b.id) : a.priority > b.priority
}
