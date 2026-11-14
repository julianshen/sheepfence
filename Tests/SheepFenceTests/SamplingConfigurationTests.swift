import Foundation
import Testing
@testable import SheepFence

@Suite struct SamplingConfigurationTests {
    @Test func standardIsTenMetersAccuracyAndFilter() throws {
        let expected = try LocationSamplingConfiguration(distanceFilterMeters: 10, desiredAccuracyMeters: 10)
        #expect(LocationSamplingConfiguration.standard == expected)
        #expect(LocationSamplingConfiguration.standard.distanceFilterMeters == 10)
        #expect(LocationSamplingConfiguration.standard.desiredAccuracyMeters == 10)
    }

    @Test func zeroDistanceFilterIsAllowedAsNoFilter() throws {
        let config = try LocationSamplingConfiguration(distanceFilterMeters: 0, desiredAccuracyMeters: 5)
        #expect(config.distanceFilterMeters == 0)
    }

    @Test func invalidValuesThrowInvalidConfiguration() {
        #expect(throws: GeofenceError.self) {
            _ = try LocationSamplingConfiguration(distanceFilterMeters: -1, desiredAccuracyMeters: 10)
        }
        #expect(throws: GeofenceError.self) {
            _ = try LocationSamplingConfiguration(distanceFilterMeters: .nan, desiredAccuracyMeters: 10)
        }
        #expect(throws: GeofenceError.self) {
            _ = try LocationSamplingConfiguration(distanceFilterMeters: .infinity, desiredAccuracyMeters: 10)
        }
        for accuracy in [-1.0, 0, .nan, .infinity] {
            #expect(throws: GeofenceError.self) {
                _ = try LocationSamplingConfiguration(distanceFilterMeters: 10, desiredAccuracyMeters: accuracy)
            }
        }
    }

    @Test func fixedConfigurationMapsToInternalProviderSettings() throws {
        let config = try LocationSamplingConfiguration(distanceFilterMeters: 25, desiredAccuracyMeters: 7)
        let settings = config.settings()
        #expect(settings == SamplingSettings(distanceFilter: 25, desiredAccuracy: 7))
        #expect(LocationSamplingConfiguration.standard.settings() == SamplingSettings(distanceFilter: 10, desiredAccuracy: 10))
    }

    @Test func samplingModeIsEquatableAndConstructible() throws {
        let fixed = SamplingMode.fixed(.standard)
        let fixedAgain = SamplingMode.fixed(.standard)
        let adaptive = SamplingMode.adaptive(try SamplingPolicyConfiguration())
        #expect(fixed == fixedAgain)
        #expect(fixed != adaptive)
        // Standard literal `.fixed(.standard)` resolves to the fixed member's type.
        let literal: SamplingMode = .fixed(.standard)
        #expect(literal == fixed)
    }

    @Test func samplingPolicyAndSettingsStayInternal() throws {
        // Internal types remain internal: this @testable-only test documents the
        // visibility boundary. SamplingSettings/SamplingPolicy must not leak into
        // the public surface (Codex's SDKContractTests covers the public side).
        let policy = SamplingPolicy(configuration: try SamplingPolicyConfiguration())
        _ = policy
    }
}
