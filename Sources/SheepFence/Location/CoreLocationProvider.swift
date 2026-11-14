import CoreLocation
import Foundation

/// MainActor wrapper over CLLocationManager. SDK never prompts; it reports
/// actual authorization, service, and accuracy state to the host.
@MainActor final class CoreLocationProvider: NSObject, LocationProvider {
    var onEvent: (@MainActor @Sendable (LocationProviderEvent) -> Void)?
    private let manager: CLLocationManager
    private var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    private var distanceFilter: CLLocationDistance = kCLDistanceFilterNone

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = desiredAccuracy
        manager.distanceFilter = distanceFilter
        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        manager.startUpdatingLocation()
        reportAvailability()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func apply(_ settings: SamplingSettings) {
        desiredAccuracy = settings.desiredAccuracy
        distanceFilter = settings.distanceFilter
        manager.desiredAccuracy = settings.desiredAccuracy
        manager.distanceFilter = settings.distanceFilter
    }

    private func reportAvailability() {
        let reason: LocationUnavailableReason?
        switch manager.authorizationStatus {
        case .notDetermined: reason = .authorizationNotDetermined
        case .restricted: reason = .authorizationRestricted
        case .denied: reason = .authorizationDenied
        default:
            reason = CLLocationManager.locationServicesEnabled() ? nil : .servicesDisabled
        }
        let reduced = manager.accuracyAuthorization == .reducedAccuracy
        onEvent?(.availability(LocationAvailability(reason: reason, reducedAccuracy: reduced)))
    }

    private func sample(from location: CLLocation) -> LocationSample {
        LocationSample(
            coordinate: Coordinate(longitude: location.coordinate.longitude, latitude: location.coordinate.latitude),
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed >= 0 ? location.speed : nil
        )
    }
}

nonisolated extension CoreLocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let sample = LocationSample(
            coordinate: Coordinate(longitude: location.coordinate.longitude, latitude: location.coordinate.latitude),
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed >= 0 ? location.speed : nil)
        // Deliver on MainActor; capture the callback reference at task creation
        // time so a later stop/restart cannot reroute a stale sample.
        let callback = MainActor.assumeIsolated { self.onEvent }
        Task { @MainActor in
            callback?(.location(sample))
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let callback = MainActor.assumeIsolated { self.onEvent }
        let reduced = manager.accuracyAuthorization == .reducedAccuracy
        let reason: LocationUnavailableReason?
        switch manager.authorizationStatus {
        case .notDetermined: reason = .authorizationNotDetermined
        case .restricted: reason = .authorizationRestricted
        case .denied: reason = .authorizationDenied
        default: reason = CLLocationManager.locationServicesEnabled() ? nil : .servicesDisabled
        }
        Task { @MainActor in
            callback?(.availability(LocationAvailability(reason: reason, reducedAccuracy: reduced)))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let reduced = manager.accuracyAuthorization == .reducedAccuracy
        let reason: LocationUnavailableReason
        if let clError = error as? CLError {
            switch clError.code {
            case .denied: reason = .authorizationDenied
            case .locationUnknown: reason = .noLocation
            default: reason = .noLocation
            }
        } else {
            reason = .noLocation
        }
        let callback = MainActor.assumeIsolated { self.onEvent }
        Task { @MainActor in
            callback?(.availability(LocationAvailability(reason: reason, reducedAccuracy: reduced)))
        }
    }
}
