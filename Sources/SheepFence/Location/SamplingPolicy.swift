import Foundation

/// Proposed facade integration API. SamplingPolicy owns a hysteresis band and
/// emits conservative near/far settings based on the nearest boundary distance.
/// Defaults are UNCALIBRATED placeholders; final values require field evidence.
public struct SamplingPolicyConfiguration: Sendable, Equatable {
    public let nearDistanceMeters: Double
    public let farDistanceMeters: Double
    public let nearDesiredAccuracy: Double
    public let farDesiredAccuracy: Double
    public let nearDistanceFilter: Double
    public let farDistanceFilter: Double
    public let speedLookaheadSeconds: Double
    public init(
        nearDistanceMeters: Double = 50,
        farDistanceMeters: Double = 100,
        nearDesiredAccuracy: Double = 5,
        farDesiredAccuracy: Double = 50,
        nearDistanceFilter: Double = 5,
        farDistanceFilter: Double = 25,
        speedLookaheadSeconds: Double = 5
    ) throws {
        guard nearDistanceMeters.isFinite, nearDistanceMeters >= 0,
              farDistanceMeters.isFinite, farDistanceMeters >= nearDistanceMeters,
              nearDesiredAccuracy.isFinite, nearDesiredAccuracy > 0,
              farDesiredAccuracy.isFinite, farDesiredAccuracy > 0,
              nearDistanceFilter.isFinite, nearDistanceFilter >= 0,
              farDistanceFilter.isFinite, farDistanceFilter >= nearDistanceFilter,
              speedLookaheadSeconds.isFinite, speedLookaheadSeconds >= 0 else {
            throw GeofenceError.invalidConfiguration("Invalid sampling policy")
        }
        self.nearDistanceMeters = nearDistanceMeters
        self.farDistanceMeters = farDistanceMeters
        self.nearDesiredAccuracy = nearDesiredAccuracy
        self.farDesiredAccuracy = farDesiredAccuracy
        self.nearDistanceFilter = nearDistanceFilter
        self.farDistanceFilter = farDistanceFilter
        self.speedLookaheadSeconds = speedLookaheadSeconds
    }
}

struct SamplingPolicy: Sendable {
    private let configuration: SamplingPolicyConfiguration
    private var currentMode: Mode = .near

    private enum Mode { case near, far }

    init(configuration: SamplingPolicyConfiguration) {
        self.configuration = configuration
    }

    mutating func settings(
        nearestBoundaryMeters: Double?,
        accuracy: Double,
        speed: Double?
    ) -> SamplingSettings {
        // Conservative: missing/nonfinite/negative inputs => near.
        let validDistance = nearestBoundaryMeters.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let validAccuracy = accuracy.isFinite && accuracy >= 0 ? accuracy : nil
        let validSpeed = speed.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }

        // Conservative: missing/nonfinite/negative accuracy => near (clearance 0).
        let effectiveClearance: Double
        if validDistance == nil || validAccuracy == nil {
            effectiveClearance = 0
        } else {
            let accuracyTerm = validAccuracy!
            let speedTerm = (validSpeed ?? 0) * configuration.speedLookaheadSeconds
            effectiveClearance = max(0, validDistance! - accuracyTerm - speedTerm)
        }

        if currentMode == .near {
            if effectiveClearance > configuration.farDistanceMeters {
                currentMode = .far
            }
        } else {
            if effectiveClearance <= configuration.nearDistanceMeters {
                currentMode = .near
            }
        }
        switch currentMode {
        case .near:
            return SamplingSettings(distanceFilter: configuration.nearDistanceFilter,
                                    desiredAccuracy: configuration.nearDesiredAccuracy)
        case .far:
            return SamplingSettings(distanceFilter: configuration.farDistanceFilter,
                                    desiredAccuracy: configuration.farDesiredAccuracy)
        }
    }
}
