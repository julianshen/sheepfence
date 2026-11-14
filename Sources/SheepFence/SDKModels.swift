import Foundation

public struct EvaluationBatch: Equatable, Sendable {
    public let evaluatedAt: Date
    public let sampleTimestamp: Date
    public let datasets: [DatasetMetadata]
    public let results: [RegionEvaluation]
    public init(evaluatedAt: Date, sampleTimestamp: Date, datasets: [DatasetMetadata], results: [RegionEvaluation]) {
        self.evaluatedAt = evaluatedAt; self.sampleTimestamp = sampleTimestamp
        self.datasets = datasets; self.results = results
    }
}
public struct DatasetSummary: Equatable, Sendable {
    public let metadata: DatasetMetadata
    public let regionCount: Int
    public let enabledRegionCount: Int
    public init(metadata: DatasetMetadata, regionCount: Int, enabledRegionCount: Int) {
        self.metadata = metadata; self.regionCount = regionCount; self.enabledRegionCount = enabledRegionCount
    }
}
public struct RegionSummary: Equatable, Sendable {
    public let id: RegionID
    public let revision: Int
    public let name: String
    public let enabled: Bool
    public let priority: Int
    public init(id: RegionID, revision: Int, name: String, enabled: Bool, priority: Int) {
        self.id = id; self.revision = revision; self.name = name; self.enabled = enabled; self.priority = priority
    }
}
public struct DatasetRemovalResult: Equatable, Sendable {
    public let datasetID: String
    public let removedRegionIDs: [RegionID]
    public let wasPresent: Bool
    public init(datasetID: String, removedRegionIDs: [RegionID], wasPresent: Bool) {
        self.datasetID = datasetID; self.removedRegionIDs = removedRegionIDs; self.wasPresent = wasPresent
    }
}
public enum DatasetReadiness: Equatable, Sendable {
    case noDatasets
    case missingRequired(Set<String>)
    case ready
}
public struct MonitoringState: Equatable, Sendable {
    public let mode: LocationSourceMode?
    public let readiness: DatasetReadiness
    public let availability: LocationAvailability
    public let datasets: [DatasetSummary]
    public let evaluations: [RegionEvaluation]
    public init(mode: LocationSourceMode?, readiness: DatasetReadiness, availability: LocationAvailability,
                datasets: [DatasetSummary], evaluations: [RegionEvaluation]) {
        self.mode = mode; self.readiness = readiness; self.availability = availability
        self.datasets = datasets; self.evaluations = evaluations
    }
}
public enum BoundaryDistanceEstimate: Equatable, Sendable {
    case approximateMeters(Double)
    case unsupported(DistanceUnsupportedReason)
}
public enum DistanceUnsupportedReason: Equatable, Sendable {
    case outsideLocalModelRange
    case numericalFailure
}
public struct RegionDistanceResult: Equatable, Sendable {
    public let regionID: RegionID
    public let revision: Int
    public let membership: Membership
    public let boundaryDistance: BoundaryDistanceEstimate
    public var distanceToBoundaryMeters: Double? {
        if case .approximateMeters(let value) = boundaryDistance { return value }
        return nil
    }
    public var distanceToRegionMeters: Double? { membership == .inside ? 0 : distanceToBoundaryMeters }
    public init(regionID: RegionID, revision: Int, membership: Membership,
                boundaryDistance: BoundaryDistanceEstimate) throws {
        if case .approximateMeters(let value) = boundaryDistance, !value.isFinite || value < 0 {
            throw GeofenceError.invalidConfiguration("Distance estimate must be finite and nonnegative")
        }
        self.regionID = regionID; self.revision = revision; self.membership = membership
        self.boundaryDistance = boundaryDistance
    }
}
public enum SourceFailure: Error, Equatable, Sendable {
    case unsupportedScheme
    case httpStatus(Int)
    case timeout
    case byteLimitExceeded(maximumBytes: Int)
    case redirectRejected
    case network
    case fileRead
}
