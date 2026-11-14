import Foundation
import Testing
@testable import SheepFence

@Suite struct ReviewRegressionTests {
    func document(rings: [[[Double]]], properties: [String: Any] = [:]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "geofenceSchema": 1,
            "dataset": ["id": "review", "revision": 1, "generatedAt": "2026-11-14T00:00:00Z"],
            "features": [["type": "Feature", "id": "r", "properties": properties,
                          "geometry": ["type": "Polygon", "coordinates": rings]]]])
    }
    let square = [[10.0,20.0],[10.01,20],[10.01,20.01],[10,20.01],[10,20]]
    @Test func numericOneIsNotBooleanSchema() throws {
        #expect(try GeoJSONDecoder.decode(document(rings: [square])).metadata.revision == 1)
    }
    @Test func numericEnabledRejected() throws {
        let data = try document(rings: [square], properties: ["enabled": 1])
        #expect(throws: GeofenceError.self) { try GeoJSONDecoder.decode(data) }
    }
    @Test func tinyNoncollinearPolygonIsValid() throws {
        let d = 0.0000001
        let ring = [[10.0,20.0],[10+d,20],[10+d,20+d],[10,20+d],[10,20]]
        let snapshot = try GeoJSONDecoder.decode(document(rings: [ring]))
        #expect(Geometry.contains(Coordinate(longitude: 10+d/2, latitude: 20+d/2), in: snapshot.regions[0].geometry))
        #expect(!Geometry.contains(Coordinate(longitude: 10+2*d, latitude: 20+d/2), in: snapshot.regions[0].geometry))
    }
    @Test func closureMustBeExact() throws {
        var ring = square
        ring[ring.count-1] = [10 + 1e-13, 20]
        let data = try document(rings: [ring])
        #expect(throws: GeofenceError.self) { try GeoJSONDecoder.decode(data) }
    }
    @Test func holeBoundaryInsideButHoleInteriorOutside() throws {
        let hole = [[10.002,20.002],[10.004,20.002],[10.004,20.004],[10.002,20.004],[10.002,20.002]]
        let snapshot = try GeoJSONDecoder.decode(document(rings: [square, hole]))
        let geometry = snapshot.regions[0].geometry
        #expect(!Geometry.contains(Coordinate(longitude: 10.003, latitude: 20.003), in: geometry))
        #expect(Geometry.contains(Coordinate(longitude: 10.002, latitude: 20.003), in: geometry))
        #expect(Geometry.distanceToBoundary(Coordinate(longitude: 10.002, latitude: 20.003), in: geometry) < 0.001)
    }
    @Test func uncertaintyCrossesDateline() throws {
        let ring = [[179.998,0.0],[179.999,0],[179.999,0.001],[179.998,0.001],[179.998,0]]
        let snapshot = try GeoJSONDecoder.decode(document(rings: [ring]))
        let region = snapshot.regions[0]
        let point = Coordinate(longitude: -179.999, latitude: 0.0005)
        #expect(Geometry.isCandidate(point, radiusMeters: 300, bounds: region.bounds))
        let distance = Geometry.distanceToBoundary(point, in: region.geometry)
        #expect(distance >= 0 && distance < 300)
    }
    @Test func coordinateLinearWidePolygonPreservesInterior() throws {
        // Each edge is <=180 degrees: this is not an unsplit dateline edge.
        let ring = [[-170.0,0.0],[0,0],[170,0],[170,1],[0,1],[-170,1],[-170,0]]
        let snapshot = try GeoJSONDecoder.decode(document(rings: [ring]))
        #expect(Geometry.contains(Coordinate(longitude: 150, latitude: 0.5), in: snapshot.regions[0].geometry))
        #expect(Geometry.contains(Coordinate(longitude: -150, latitude: 0.5), in: snapshot.regions[0].geometry))
        #expect(!Geometry.contains(Coordinate(longitude: 175, latitude: 0.5), in: snapshot.regions[0].geometry))
    }
    @Test func integerOverflowRejectedWithoutTrapping() throws {
        let raw = #"{"type":"FeatureCollection","geofenceSchema":1,"dataset":{"id":"d","revision":9223372036854775808,"generatedAt":"2026-11-14T00:00:00Z"},"features":[]}"#
        #expect(throws: GeofenceError.self) { try GeoJSONDecoder.decode(Data(raw.utf8)) }
    }
}
