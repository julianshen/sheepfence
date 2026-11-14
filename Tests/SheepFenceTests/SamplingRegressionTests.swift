import Testing
@testable import SheepFence

@Suite struct SamplingRegressionTests {
    @Test func uncertaintyDiskNearBoundaryMustUseDenseSampling() throws {
        var policy = SamplingPolicy(configuration: try SamplingPolicyConfiguration())
        let settings = policy.settings(nearestBoundaryMeters: 150, accuracy: 200, speed: nil)
        #expect(settings.distanceFilter == 5)
        #expect(settings.desiredAccuracy == 5)
    }

    @Test func unknownAccuracyMustNotRelaxSampling() throws {
        var policy = SamplingPolicy(configuration: try SamplingPolicyConfiguration())
        _ = policy.settings(nearestBoundaryMeters: 500, accuracy: 1, speed: nil)
        let settings = policy.settings(nearestBoundaryMeters: 500, accuracy: .nan, speed: nil)
        #expect(settings.distanceFilter == 5)
    }

    @Test func zeroAccuracyIsValidAndHysteresisWorksBothDirections() throws {
        var policy = SamplingPolicy(configuration: try SamplingPolicyConfiguration())
        #expect(policy.settings(nearestBoundaryMeters: 10, accuracy: 0, speed: nil).distanceFilter == 5)
        #expect(policy.settings(nearestBoundaryMeters: 75, accuracy: 0, speed: nil).distanceFilter == 5)
        #expect(policy.settings(nearestBoundaryMeters: 150, accuracy: 0, speed: nil).distanceFilter == 25)
        #expect(policy.settings(nearestBoundaryMeters: 75, accuracy: 0, speed: nil).distanceFilter == 25)
        #expect(policy.settings(nearestBoundaryMeters: 10, accuracy: 0, speed: nil).distanceFilter == 5)
    }
}
