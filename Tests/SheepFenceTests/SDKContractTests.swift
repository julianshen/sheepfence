import Foundation
import Testing
import SheepFence

struct SDKContractTests {
    @Test func unsupportedDistanceDoesNotMasqueradeAsZero() throws {
        let id = RegionID(datasetID: "d", featureID: "r")
        let outside = try RegionDistanceResult(regionID: id, revision: 1, membership: .outside,
                                               boundaryDistance: .unsupported(.outsideLocalModelRange))
        #expect(outside.distanceToBoundaryMeters == nil)
        #expect(outside.distanceToRegionMeters == nil)
        let inside = try RegionDistanceResult(regionID: id, revision: 1, membership: .inside,
                                              boundaryDistance: .unsupported(.outsideLocalModelRange))
        #expect(inside.distanceToRegionMeters == 0)
        #expect(inside.distanceToBoundaryMeters == nil)
        for value in [-1.0, .nan, .infinity] {
            #expect(throws: GeofenceError.self) {
                try RegionDistanceResult(regionID: id, revision: 1, membership: .outside,
                                         boundaryDistance: .approximateMeters(value))
            }
        }
    }
    @Test func resultPayloadsConstructibleOutsideModule() {
        let metadata = DatasetMetadata(id: "d", revision: 1, generatedAt: Date(timeIntervalSince1970: 0))
        let summary = DatasetSummary(metadata: metadata, regionCount: 0, enabledRegionCount: 0)
        let state = MonitoringState(mode: nil, readiness: .ready,
            availability: .init(reason: .monitoringStopped), datasets: [summary], evaluations: [])
        #expect(state.datasets.first?.metadata == metadata)
        let batch = EvaluationBatch(evaluatedAt: metadata.generatedAt, sampleTimestamp: metadata.generatedAt,
                                    datasets: [metadata], results: [])
        #expect(batch.results.isEmpty)
    }
}
