import Foundation
import Testing
@testable import SheepFence

/// Run explicitly in Release with coverage disabled; results are not device gates.
@Suite(.serialized) struct CapacityBenchmarkTests {
    @Test func hundredAreas() async throws {
        let warmup = 200, measured = 2_000
        for overlapping in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try CoreDataSnapshotStore(url: directory.appendingPathComponent("benchmark.sqlite"))
            let bytes = try CapacityFixtureFactory.make(overlapping: overlapping)
            let snapshot = try GeoJSONDecoder.decode(bytes)
            _ = try await store.commit(snapshot)
            let restored = try await store.loadCommittedSnapshots()
            let engine = GeofenceEngine(
                configuration: try GeofenceConfiguration(maximumLocationAge: 1_000_000),
                store: store, source: UnusedSource(), decoder: { try GeoJSONDecoder.decode($0) },
                geometry: GeometryOperations(contains: { Geometry.contains($0, in: $1) },
                    distance: { Geometry.distanceToBoundary($0, in: $1) },
                    candidate: { Geometry.isCandidate($0, radiusMeters: $1, bounds: $2) }),
                clock: FixedClock(time: Date(timeIntervalSince1970: 1_000_000)), snapshots: restored)
            #expect(restored.count == 1 && restored[0].regions.count == 100)
            let allIDs = Set((0..<100).map { String(format: "region-%03d", $0) })
            var milliseconds: [Double] = []
            milliseconds.reserveCapacity(measured)
            let clock = ContinuousClock()
            let readsBefore = store.readCountSnapshot
            for index in 0..<(warmup + measured) {
                let region = index % 100
                let sample = LocationSample(
                    coordinate: Coordinate(longitude: overlapping ? 10 : 10 + Double(region) * 0.05, latitude: 20),
                    timestamp: Date(timeIntervalSince1970: 1000 + Double(index)), horizontalAccuracy: 1)
                let start = clock.now
                let results = try await engine.evaluateOnce(location: sample).results
                let elapsed = start.duration(to: clock.now).components
                if index >= warmup {
                    milliseconds.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
                }
                // Oracle work is outside the timed interval, including set allocation.
                let inside = Set(results.filter { $0.observation == .confirmed(.inside) }.map(\.regionID.featureID))
                let expected = overlapping ? allIDs : [String(format: "region-%03d", region)]
                #expect(results.count == 100 && inside == expected)
            }
            let storeOperations = store.readCountSnapshot - readsBefore
            #expect(storeOperations == 0)
            milliseconds.sort()
            func percentile(_ fraction: Double) -> Double {
                milliseconds[max(0, Int(ceil(Double(milliseconds.count) * fraction)) - 1)]
            }
            let report: [String: Any] = [
                "layout": overlapping ? "overlapping" : "separated", "areas": 100, "edgesPerArea": 100,
                "warmup": warmup, "samples": measured, "p50_ms": percentile(0.5), "p95_ms": percentile(0.95),
                "p99_ms": percentile(0.99), "max_ms": milliseconds.last!,
                "mean_ms": milliseconds.reduce(0, +) / Double(measured),
                "storeOperationsDuringQueries": storeOperations,
                "datasetSHA256": snapshot.sha256.map { String(format: "%02x", $0) }.joined(),
                "horizontalAccuracyMeters": 1, "bufferMeters": 0, "revision": 1
            ]
            let json = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            print("SHEEPFENCE_BENCHMARK " + String(decoding: json, as: UTF8.self))
        }
    }
}
