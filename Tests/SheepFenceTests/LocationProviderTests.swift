import Foundation
import CoreLocation
import Testing
@testable import SheepFence

private final class ReducedAccuracyManager: CLLocationManager {
    override var accuracyAuthorization: CLAccuracyAuthorization { .reducedAccuracy }
    override var authorizationStatus: CLAuthorizationStatus { .authorizedAlways }
}

/// Injected authorization state; never depends on the host's live status.
private final class AuthStatusManager: CLLocationManager {
    private let status: CLAuthorizationStatus
    init(status: CLAuthorizationStatus) {
        self.status = status
        super.init()
    }
    override var authorizationStatus: CLAuthorizationStatus { status }
    override var accuracyAuthorization: CLAccuracyAuthorization { .fullAccuracy }
}

@MainActor @Suite struct LocationProviderTests {
    @Test func coreProviderAppliesSamplingSettings() {
        let manager = CLLocationManager()
        let provider = CoreLocationProvider(manager: manager)
        provider.apply(SamplingSettings(distanceFilter: 10, desiredAccuracy: 5))
        #expect(manager.distanceFilter == 10)
        #expect(manager.desiredAccuracy == 5)
        provider.stop()
    }

    @Test func queuedLocationRetainsOriginalCallback() async throws {
        let manager = CLLocationManager()
        let provider = CoreLocationProvider(manager: manager)
        // Drive delegate methods directly; do not mix live OS authorization callbacks
        // into this deterministic delivery test.
        manager.delegate = nil
        let (stream, continuation) = AsyncStream<LocationProviderEvent>.makeStream()
        provider.onEvent = { continuation.yield($0) }
        provider.locationManager(manager, didUpdateLocations: [CLLocation(latitude: 20, longitude: 10)])
        provider.stop()
        var deliveredToNewSession = false
        provider.onEvent = { _ in deliveredToNewSession = true }
        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()
        if case .location(let sample) = event { #expect(sample.coordinate.longitude == 10) }
        else { Issue.record("Expected captured location callback") }
        #expect(!deliveredToNewSession)
        continuation.finish()
        provider.onEvent = nil
    }

    @Test func providerErrorsHaveExplicitReasons() async throws {
        let manager = ReducedAccuracyManager()
        let provider = CoreLocationProvider(manager: manager)
        manager.delegate = nil
        let (stream, continuation) = AsyncStream<LocationProviderEvent>.makeStream()
        provider.onEvent = { continuation.yield($0) }
        var iterator = stream.makeAsyncIterator()
        for (code, expected) in [(CLError.denied, LocationUnavailableReason.authorizationDenied),
                                  (.locationUnknown, .noLocation), (.network, .noLocation)] {
            let reducedAtDelivery = manager.accuracyAuthorization == .reducedAccuracy
            provider.locationManager(manager, didFailWithError: CLError(code))
            let event = await iterator.next()
            if case .availability(let availability) = event {
                #expect(availability.reason == expected)
                #expect(availability.reducedAccuracy == reducedAtDelivery)
            } else { Issue.record("Expected availability callback") }
        }
        continuation.finish()
        provider.onEvent = nil
    }

    @Test func samplingPolicyHysteresis() throws {
        var policy = SamplingPolicy(configuration: try SamplingPolicyConfiguration(nearDistanceMeters: 50, farDistanceMeters: 100))
        let near = policy.settings(nearestBoundaryMeters: 10, accuracy: 5, speed: nil)
        let far = policy.settings(nearestBoundaryMeters: 150, accuracy: 5, speed: nil)
        let stillNear = policy.settings(nearestBoundaryMeters: 75, accuracy: 5, speed: nil)
        #expect(near.distanceFilter == 5)
        #expect(far.distanceFilter == 25)
        #expect(stillNear.distanceFilter == 25)
    }

    @Test func samplingPolicyConservativeOnMissingInputs() throws {
        var policy = SamplingPolicy(configuration: try SamplingPolicyConfiguration())
        // Missing distance => near (conservative)
        let missing = policy.settings(nearestBoundaryMeters: nil, accuracy: 5, speed: nil)
        #expect(missing.distanceFilter == 5)
        // Negative accuracy => near
        let negAcc = policy.settings(nearestBoundaryMeters: 1000, accuracy: -1, speed: nil)
        #expect(negAcc.distanceFilter == 5)
        // Accuracy zero is valid
        let zeroAcc = policy.settings(nearestBoundaryMeters: 1000, accuracy: 0, speed: nil)
        #expect(zeroAcc.distanceFilter == 25)
    }

    @Test func samplingPolicyAccuracyAffectsClearance() throws {
        var policy = SamplingPolicy(configuration: try SamplingPolicyConfiguration(nearDistanceMeters: 50, farDistanceMeters: 100))
        // distance 150, accuracy 200 => effective clearance 0 => near
        let near = policy.settings(nearestBoundaryMeters: 150, accuracy: 200, speed: nil)
        #expect(near.distanceFilter == 5)
        // Reset
        var policy2 = SamplingPolicy(configuration: try SamplingPolicyConfiguration(nearDistanceMeters: 50, farDistanceMeters: 100))
        let far = policy2.settings(nearestBoundaryMeters: 150, accuracy: 5, speed: nil)
        #expect(far.distanceFilter == 25)
    }

    @Test func authorizationStatesMapToExplicitReasons() async throws {
        // Deterministic injected status; the Mac's live authorization never decides.
        for (status, expected) in [
            (CLAuthorizationStatus.notDetermined, LocationUnavailableReason.authorizationNotDetermined),
            (.restricted, .authorizationRestricted),
            (.denied, .authorizationDenied),
        ] {
            let manager = AuthStatusManager(status: status)
            let provider = CoreLocationProvider(manager: manager)
            manager.delegate = nil
            let (stream, continuation) = AsyncStream<LocationProviderEvent>.makeStream()
            provider.onEvent = { continuation.yield($0) }
            var iterator = stream.makeAsyncIterator()
            provider.start()
            let event = await iterator.next()
            if case .availability(let availability) = event {
                #expect(availability.reason == expected)
                #expect(!availability.reducedAccuracy)
            } else { Issue.record("Expected availability callback for \(status)") }
            provider.stop()
            continuation.finish()
            provider.onEvent = nil
        }
    }

    @Test func startReportsAvailabilityOncePerStart() async throws {
        let manager = AuthStatusManager(status: .authorizedAlways)
        let provider = CoreLocationProvider(manager: manager)
        manager.delegate = nil
        let (stream, continuation) = AsyncStream<LocationProviderEvent>.makeStream()
        provider.onEvent = { continuation.yield($0) }
        var iterator = stream.makeAsyncIterator()
        provider.start()
        let first = await iterator.next()
        if case .availability(let availability) = first {
            #expect(availability.reason == nil)  // allowed with services enabled
        } else { Issue.record("Expected initial availability callback") }
        provider.stop()
        continuation.finish()
        provider.onEvent = nil
    }

    @Test func samplingPolicySpeedLookaheadAffectsClearance() throws {
        var policy = SamplingPolicy(configuration: try SamplingPolicyConfiguration(nearDistanceMeters: 50, farDistanceMeters: 100, speedLookaheadSeconds: 10))
        // distance 150, speed 20 => 150 - 0 - 200 = -50 => near
        let near = policy.settings(nearestBoundaryMeters: 150, accuracy: 0, speed: 20)
        #expect(near.distanceFilter == 5)
    }

    @Test func samplingPolicyHysteresisBothDirections() throws {
        var policy = SamplingPolicy(configuration: try SamplingPolicyConfiguration(nearDistanceMeters: 50, farDistanceMeters: 100))
        // Start near, go far, come back near
        _ = policy.settings(nearestBoundaryMeters: 10, accuracy: 0, speed: nil) // near
        let far = policy.settings(nearestBoundaryMeters: 150, accuracy: 0, speed: nil) // far
        #expect(far.distanceFilter == 25)
        let near = policy.settings(nearestBoundaryMeters: 10, accuracy: 0, speed: nil) // near
        #expect(near.distanceFilter == 5)
    }
}
