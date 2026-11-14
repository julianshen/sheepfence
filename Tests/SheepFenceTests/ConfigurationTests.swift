import Foundation
import Testing
@testable import SheepFence

@Test func configurationPreservesExplicitPolicy() throws {
    let configuration = try GeofenceConfiguration(maximumLocationAge: 30, boundaryBufferMeters: 5)
    #expect(configuration.maximumLocationAge == 30)
    #expect(configuration.boundaryBufferMeters == 5)
}

@Test(arguments: [0.0, -1, Double.infinity, -Double.infinity, Double.nan])
func rejectsInvalidLocationAge(_ age: Double) {
    #expect(throws: GeofenceError.self) {
        try GeofenceConfiguration(maximumLocationAge: age)
    }
}

@Test(arguments: [-1.0, Double.infinity, -Double.infinity, Double.nan])
func rejectsInvalidBoundaryBuffer(_ buffer: Double) {
    #expect(throws: GeofenceError.self) {
        try GeofenceConfiguration(maximumLocationAge: 30, boundaryBufferMeters: buffer)
    }
}

@Test func regionIdentityIncludesDataset() {
    let first = RegionID(datasetID: "first", featureID: "garden")
    let second = RegionID(datasetID: "second", featureID: "garden")
    #expect(Set([first, second]).count == 2)
}
