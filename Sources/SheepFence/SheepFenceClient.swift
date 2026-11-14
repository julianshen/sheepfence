import Foundation

/// Foreground lifecycle facade. Permission prompts and scene lifecycle remain host-owned.
@MainActor public final class SheepFenceClient: GeofenceClient {
    private let engine: GeofenceEngine
    private let provider: any LocationProvider
    private let sampling: @Sendable (Double?, LocationSample) -> SamplingSettings
    private var mode: LocationSourceMode?
    private var providerRunning = false
    private var generation: UInt64 = 0
    private var lifecycleTail: Task<Void, Never>?

    init(engine: GeofenceEngine, provider: any LocationProvider,
         sampling: @escaping @Sendable (Double?, LocationSample) -> SamplingSettings) {
        self.engine = engine; self.provider = provider; self.sampling = sampling
    }

    public func events() async -> AsyncStream<GeofenceEvent> { await engine.events() }
    public func query(coordinate: Coordinate, in region: RegionID) async throws -> GeometryQueryResult {
        try await engine.query(coordinate: coordinate, in: region)
    }
    public func evaluate(location: LocationSample) async throws -> [RegionEvaluation] {
        try await engine.evaluate(location: location)
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
                        await self.engine.reportEvaluationFailure(.storageFailed(String(describing: error)), generation: engineGeneration)
                        return
                    }
                    guard !results.isEmpty, self.generation == epoch, self.mode == .sdkManaged else { return }
                    let nearest = await self.engine.nearestBoundary(to: sample)
                    guard self.generation == epoch, self.mode == .sdkManaged else { return }
                    self.provider.apply(self.sampling(nearest, sample))
                }
            }
        }
        providerRunning = true
        provider.start()
    }
}
