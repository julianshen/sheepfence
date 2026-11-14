import Foundation

struct MonitoringSession: Sendable {
    private(set) var mode: LocationSourceMode?
    private(set) var generation: UInt64 = 0
    @discardableResult mutating func start(_ requested: LocationSourceMode) throws -> Bool {
        if let mode {
            guard mode == requested else { throw GeofenceError.sourceModeConflict }
            return false
        }
        mode = requested
        generation &+= 1
        return true
    }
    @discardableResult mutating func stop() -> Bool {
        guard mode != nil else { return false }
        mode = nil; generation &+= 1
        return true
    }
    func requireHostSource() throws {
        if mode == .sdkManaged { throw GeofenceError.sourceModeConflict }
    }
}

struct DatasetReadiness {
    static func check(installed: Set<String>, expected: Set<String>) throws {
        if let missing = expected.subtracting(installed).sorted().first {
            throw GeofenceError.datasetNotReady(missing)
        }
        guard !installed.isEmpty else { throw GeofenceError.datasetNotReady(nil) }
    }
}
