import Foundation
import Testing
@testable import SheepFence

extension GeofenceEngine {
    func submitResults(location: LocationSample) async throws -> [RegionEvaluation] {
        try startMonitoring(mode: .hostProvided)
        return try submit(location: location).results
    }
    func transitionEventsForTests() -> AsyncStream<GeofenceEvent> {
        do {
            let source = try eventStream(bufferCapacity: 2048)
            return AsyncStream { continuation in
                let worker = Task {
                    do {
                        for try await event in source {
                            switch event {
                            case .stateSnapshot, .evaluated: continue
                            case .locationAvailabilityChanged(let value) where value.reason != .servicesDisabled: continue
                            default: continuation.yield(event)
                            }
                        }
                    } catch { Issue.record("Unexpected event stream error: \(error)") }
                    continuation.finish()
                }
                continuation.onTermination = { _ in worker.cancel() }
            }
        } catch {
            Issue.record("Cannot subscribe: \(error)")
            return AsyncStream { $0.finish() }
        }
    }
}
