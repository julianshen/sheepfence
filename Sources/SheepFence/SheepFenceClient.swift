import Foundation

/// Foreground lifecycle facade. Permission prompts and scene lifecycle remain host-owned.
@MainActor public final class SheepFenceClient: GeofenceClient {
    private let engine: GeofenceEngine
    private let provider: any LocationProvider
    private let usesAdaptiveSampling: Bool
    private let sampling: @MainActor @Sendable (Double?, LocationSample) -> SamplingSettings
    private let resetSampling: @MainActor @Sendable () -> SamplingSettings?
    private var mode: LocationSourceMode?
    private var providerRunning = false
    private var generation: UInt64 = 0
    private var lifecycleTail: Task<Void, Never>?

    init(engine: GeofenceEngine, provider: any LocationProvider,
         sampling: @escaping @MainActor @Sendable (Double?, LocationSample) -> SamplingSettings,
         resetSampling: @escaping @MainActor @Sendable () -> SamplingSettings? = { nil },
         usesAdaptiveSampling: Bool = true) {
        self.engine = engine; self.provider = provider; self.sampling = sampling
        self.usesAdaptiveSampling = usesAdaptiveSampling
        self.resetSampling = resetSampling
    }

    deinit {
        let ownedProvider = provider
        Task { @MainActor in ownedProvider.onEvent = nil; ownedProvider.stop() }
    }

    /// Restores committed datasets. One live client is permitted per canonical store URL.
    public static func open(storeURL: URL, configuration: GeofenceConfiguration) async throws -> SheepFenceClient {
        try Task.checkCancellation()
        let lease = try StoreLease.acquire(for: storeURL)
        let store: CoreDataSnapshotStore
        let snapshots: [ValidatedSnapshot]
        do {
            (store, snapshots) = try await Task.detached {
                // Retain lease across detached initialization even if caller is cancelled.
                let store = try CoreDataSnapshotStore(url: lease.url)
                return (store, try await store.loadCommittedSnapshots())
            }.value
            try Task.checkCancellation()
        } catch {
            if error is CancellationError || error is GeofenceError { throw error }
            throw GeofenceError.storageFailed("Could not open the snapshot store")
        }
        let engine = GeofenceEngine(configuration: configuration, store: store,
            source: HTTPSnapshotSource(policy: configuration.downloadPolicy), decoder: { try GeoJSONDecoder.decode($0) },
            geometry: GeometryOperations(contains: { Geometry.contains($0, in: $1) },
                distance: { Geometry.distanceToBoundary($0, in: $1) },
                candidate: { Geometry.isCandidate($0, radiusMeters: $1, bounds: $2) }),
            snapshots: snapshots, storeLease: lease)
        switch configuration.sampling {
        case .fixed(let fixed):
            let settings = SamplingSettings(distanceFilter: fixed.distanceFilterMeters, desiredAccuracy: fixed.desiredAccuracyMeters)
            return SheepFenceClient(engine: engine, provider: CoreLocationProvider(),
                sampling: { _, _ in settings }, resetSampling: { settings }, usesAdaptiveSampling: false)
        case .adaptive(let configuration):
            var policy = SamplingPolicy(configuration: configuration)
            return SheepFenceClient(engine: engine, provider: CoreLocationProvider(),
                sampling: { distance, sample in
                    policy.settings(nearestBoundaryMeters: distance, accuracy: sample.horizontalAccuracy, speed: sample.speed)
                }, resetSampling: {
                    policy = SamplingPolicy(configuration: configuration)
                    return policy.settings(nearestBoundaryMeters: nil, accuracy: .infinity, speed: nil)
                })
        }
    }

    @available(*, deprecated, message: "Place downloadPolicy and sampling in GeofenceConfiguration and use open(storeURL:configuration:)")
    public static func open(storeURL: URL, configuration: GeofenceConfiguration,
                            downloadPolicy: DownloadPolicy,
                            samplingConfiguration: SamplingPolicyConfiguration) async throws -> SheepFenceClient {
        try await open(storeURL: storeURL, configuration: GeofenceConfiguration(
            maximumLocationAge: configuration.maximumLocationAge,
            boundaryBufferMeters: configuration.boundaryBufferMeters,
            maximumFutureSkew: configuration.maximumFutureSkew, expectedDatasetIDs: configuration.expectedDatasetIDs,
            downloadPolicy: downloadPolicy, sampling: .adaptive(samplingConfiguration)))
    }

    public func events(bufferCapacity: Int = 256) async throws -> AsyncThrowingStream<GeofenceEvent, Error> {
        try await engine.eventStream(bufferCapacity: bufferCapacity)
    }
    public func state() async -> MonitoringState { await engine.currentState() }
    public func datasets() async -> [DatasetSummary] { await engine.datasets() }
    public func regions(in datasetID: String? = nil) async throws -> [RegionSummary] { try await engine.regions(in: datasetID) }
    public func distance(from coordinate: Coordinate, to region: RegionID) async throws -> RegionDistanceResult {
        try await engine.distance(from: coordinate, to: region)
    }
    public func removeDataset(id: String) async throws -> DatasetRemovalResult {
        let result = try await engine.removeDataset(id: id)
        try await serializeLifecycle { await self.refreshProvider() }
        return result
    }
    public func installSnapshot(data: Data) async throws -> InstallResult {
        let result = try await engine.install(data: data)
        try await serializeLifecycle { await self.refreshProvider() }
        return result
    }
    public func query(coordinate: Coordinate, in region: RegionID) async throws -> GeometryQueryResult {
        try await engine.query(coordinate: coordinate, in: region)
    }
    /// Pure one-shot evaluation; never changes monitoring history or emits events.
    public func evaluate(location: LocationSample) async throws -> EvaluationBatch {
        try await engine.evaluateOnce(location: location)
    }
    public func submit(location: LocationSample) async throws -> EvaluationBatch {
        try await engine.submit(location: location)
    }
    public func updateAvailability(_ availability: LocationAvailability) async throws {
        try await engine.updateAvailability(availability)
    }
    public func installSnapshot(from source: URL) async throws -> InstallResult {
        let result = try await engine.installSnapshot(from: source)
        try await serializeLifecycle { await self.refreshProvider() }
        return result
    }
    public func startMonitoring(mode requested: LocationSourceMode) async throws {
        try await serializeLifecycle {
            if let mode = self.mode {
                guard mode == requested else { throw GeofenceError.sourceModeConflict }
                return
            }
            try await self.engine.startMonitoring(mode: requested)
            self.mode = requested
            self.generation &+= 1
            await self.refreshProvider()
        }
    }
    public func stopMonitoring() async {
        try? await serializeLifecycle {
            guard self.mode != nil || self.providerRunning else { return }
            self.generation &+= 1
            self.provider.onEvent = nil
            self.provider.stop()
            self.providerRunning = false
            self.mode = nil
            await self.engine.stopMonitoring()
        }
    }
    private func serializeLifecycle(_ operation: @escaping @MainActor @Sendable () async throws -> Void) async throws {
        let previous = lifecycleTail
        let task = Task { @MainActor in
            await previous?.value
            try await operation()
        }
        lifecycleTail = Task { _ = try? await task.value }
        try await task.value
    }
    private func refreshProvider() async {
        guard mode == .sdkManaged else { return }
        let epoch = generation
        let enabled = await engine.hasEnabledRegions()
        guard mode == .sdkManaged, generation == epoch else { return }
        if !enabled {
            if providerRunning { generation &+= 1 }
            provider.onEvent = nil
            provider.stop()
            providerRunning = false
            return
        }
        guard !providerRunning else { return }
        let engineGeneration = await engine.monitoringGeneration()
        guard generation == epoch, mode == .sdkManaged else { return }
        provider.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, self.mode == .sdkManaged, self.generation == epoch else { return }
                switch event {
                case .availability(let availability):
                    await self.engine.receiveAvailability(availability, generation: engineGeneration)
                case .location(let sample):
                    let results: [RegionEvaluation]
                    do { results = try await self.engine.receive(sample, generation: engineGeneration) }
                    catch let error as GeofenceError {
                        await self.engine.reportEvaluationFailure(error, generation: engineGeneration)
                        return
                    } catch {
                        await self.engine.reportEvaluationFailure(.storageFailed("Provider evaluation failed"), generation: engineGeneration)
                        return
                    }
                    guard !results.isEmpty, self.generation == epoch, self.mode == .sdkManaged else { return }
                    let nearest = self.usesAdaptiveSampling ? await self.engine.nearestBoundary(to: sample) : nil
                    guard self.generation == epoch, self.mode == .sdkManaged else { return }
                    self.provider.apply(self.sampling(nearest, sample))
                }
            }
        }
        providerRunning = true
        if let initial = resetSampling() { provider.apply(initial) }
        provider.start()
    }
}
