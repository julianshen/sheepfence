import Foundation

/// Stable identity across dataset revisions and display-name changes.
public struct RegionID: Hashable, Codable, Sendable {
    public let datasetID: String
    public let featureID: String

    public init(datasetID: String, featureID: String) {
        self.datasetID = datasetID
        self.featureID = featureID
    }
}

public struct DatasetMetadata: Equatable, Codable, Sendable {
    public let id: String
    public let revision: Int
    public let generatedAt: Date

    public init(id: String, revision: Int, generatedAt: Date) {
        self.id = id
        self.revision = revision
        self.generatedAt = generatedAt
    }
}

public enum Membership: String, Codable, Sendable {
    case inside, outside
}

public enum LocationUnavailableReason: Equatable, Sendable {
    case authorizationNotDetermined
    case authorizationDenied
    case authorizationRestricted
    case servicesDisabled
    case staleLocation
    case futureLocation
    case outOfOrderLocation
    case invalidAccuracy
    case invalidCoordinate
    case noLocation
    case monitoringStopped
}

public struct ConfirmedState: Equatable, Sendable {
    public let membership: Membership
    public let observedAt: Date
    public let revision: Int

    public init(membership: Membership, observedAt: Date, revision: Int) {
        self.membership = membership
        self.observedAt = observedAt
        self.revision = revision
    }
}

public enum Observation: Equatable, Sendable {
    case confirmed(Membership)
    case boundaryUncertain
    case unavailable(LocationUnavailableReason)
}

public struct RegionEvaluation: Equatable, Sendable {
    public let regionID: RegionID
    public let revision: Int
    public let observedAt: Date
    public let observation: Observation
    public let lastConfirmed: ConfirmedState?

    public init(
        regionID: RegionID, revision: Int, observedAt: Date,
        observation: Observation, lastConfirmed: ConfirmedState?
    ) {
        self.regionID = regionID
        self.revision = revision
        self.observedAt = observedAt
        self.observation = observation
        self.lastConfirmed = lastConfirmed
    }
}

public enum InstallOutcome: Equatable, Sendable {
    case installed
    case unchanged
    case olderVersionSkipped
}

/// The submitted dataset and the revision effective after the operation.
public struct InstallResult: Equatable, Sendable {
    public let dataset: DatasetMetadata
    public let activeRevision: Int
    public let outcome: InstallOutcome

    public init(dataset: DatasetMetadata, activeRevision: Int, outcome: InstallOutcome) {
        self.dataset = dataset
        self.activeRevision = activeRevision
        self.outcome = outcome
    }
}

public enum GeofenceError: Error, Equatable, Sendable {
    case sourceFailed(SourceFailure)
    case storeAlreadyOpen
    case eventBufferOverflow
    case invalidConfiguration(String)
    case invalidCoordinate
    case sourceModeConflict
    case monitoringNotStarted
    case datasetNotReady(String?)
    case regionNotFound(RegionID)
    case invalidSnapshot(regionID: String?, path: String, reason: String)
    case unsupportedSchema(Int)
    case revisionConflict(datasetID: String, revision: Int)
    case unsupportedSource(URL)
    case downloadFailed(String)
    case storageFailed(String)
}
