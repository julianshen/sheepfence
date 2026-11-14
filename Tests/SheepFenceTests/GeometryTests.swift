import Foundation
import Testing
@testable import SheepFence

@Suite struct GeometryTests {
    private func poly(_ rings: [[Coordinate]]) -> RegionGeometry { RegionGeometry(polygons: [Polygon(rings: rings)]) }
    private func square(_ minLon: Double, _ minLat: Double, _ size: Double) -> [[Coordinate]] {
        let r = [Coordinate(longitude:minLon,latitude:minLat), Coordinate(longitude:minLon+size,latitude:minLat), Coordinate(longitude:minLon+size,latitude:minLat+size), Coordinate(longitude:minLon,latitude:minLat+size), Coordinate(longitude:minLon,latitude:minLat)]
        return [r]
    }

    @Test func boundariesInsideHolesOutside() {
        let shell = [Coordinate(longitude:0,latitude:0),Coordinate(longitude:4,latitude:0),Coordinate(longitude:4,latitude:4),Coordinate(longitude:0,latitude:4),Coordinate(longitude:0,latitude:0)]
        let hole = [Coordinate(longitude:1,latitude:1),Coordinate(longitude:1,latitude:2),Coordinate(longitude:2,latitude:2),Coordinate(longitude:2,latitude:1),Coordinate(longitude:1,latitude:1)]
        let g = poly([shell, hole])
        #expect(Geometry.contains(Coordinate(longitude: 0.5, latitude: 0.5), in: g))
        #expect(Geometry.contains(Coordinate(longitude: 0, latitude: 2), in: g)) // outer boundary
        #expect(Geometry.contains(Coordinate(longitude: 1, latitude: 1.5), in: g)) // hole boundary
        #expect(!Geometry.contains(Coordinate(longitude: 1.5, latitude: 1.5), in: g)) // hole interior
        #expect(!Geometry.contains(Coordinate(longitude: -1, latitude: 2), in: g))
    }

    @Test func multiPolygonSecondComponentAndSignedCoordinates() {
        let g = RegionGeometry(polygons: [
            Polygon(rings: [[Coordinate(longitude:-10,latitude:-10),Coordinate(longitude:-9,latitude:-10),Coordinate(longitude:-9,latitude:-9),Coordinate(longitude:-10,latitude:-9),Coordinate(longitude:-10,latitude:-10)]]),
            Polygon(rings: [[Coordinate(longitude:20,latitude:30),Coordinate(longitude:21,latitude:30),Coordinate(longitude:21,latitude:31),Coordinate(longitude:20,latitude:31),Coordinate(longitude:20,latitude:30)]])
        ])
        #expect(!Geometry.contains(Coordinate(longitude: 0, latitude: 0), in: g))
        #expect(Geometry.contains(Coordinate(longitude: 20.5, latitude: 30.5), in: g))
    }

    @Test func distanceToBoundaryEndpointsAndAxes() {
        let g = poly(square(10, 20, 0.01)) // ~1.11km square approx
        let onEdge = Geometry.distanceToBoundary(Coordinate(longitude: 10, latitude: 20.005), in: g)
        #expect(onEdge <= 0.01)
        let inside = Coordinate(longitude: 10.002, latitude: 20.005)
        let d = Geometry.distanceToBoundary(inside, in: g)
        #expect(d > 150 && d < 300) // ~222m to west edge at lat20
        // endpoint nearest: point near corner outside-ish in projection along diagonal inside
        let cornerDir = Geometry.distanceToBoundary(Coordinate(longitude: 10.0001, latitude: 20.0001), in: g)
        #expect(cornerDir >= 0)
    }

    @Test func periodicDatelineCandidateAndDistance() {
        // region near +179.999 to 180 side represented as 179.999..180 (small) - but use split-valid component near 179.999
        let ring = [Coordinate(longitude:179.999,latitude:0),Coordinate(longitude:179.9995,latitude:0),Coordinate(longitude:179.9995,latitude:0.001),Coordinate(longitude:179.999,latitude:0.001),Coordinate(longitude:179.999,latitude:0)]
        let g = poly([ring])
        let b = [RegionBounds(minLongitude:179.999,minLatitude:0,maxLongitude:179.9995,maxLatitude:0.001)]
        let p = Coordinate(longitude: -179.9992, latitude: 0.0005) // across dateline, ~33m away in lon approx
        #expect(Geometry.isCandidate(p, radiusMeters: 500, bounds: b))
        let d = Geometry.distanceToBoundary(p, in: g)
        #expect(d < 200) // should be small across dateline, not ~40000km
    }

    @Test func isCandidateConservativeAndCanExclude() {
        let b = [RegionBounds(minLongitude:10,minLatitude:20,maxLongitude:10.001,maxLatitude:20.001)]
        #expect(Geometry.isCandidate(Coordinate(longitude:10.0005,latitude:20.0005), radiusMeters: 10, bounds: b))
        #expect(!Geometry.isCandidate(Coordinate(longitude:10.1,latitude:20.1), radiusMeters: 10, bounds: b))
        // high latitude conservative
        #expect(Geometry.isCandidate(Coordinate(longitude:10,latitude:86), radiusMeters: 1, bounds: [RegionBounds(minLongitude:50,minLatitude:85,maxLongitude:51,maxLatitude:86)]))
    }

    @Test func smallPolygonNotRejectedByFixedEpsilon() {
        // ~1e-7 degree square (~1cm) around lon10 lat20: must be representable and inside detectable
        let d = 1e-7
        let ring = [Coordinate(longitude:10,latitude:20),Coordinate(longitude:10+d,latitude:20),Coordinate(longitude:10+d,latitude:20+d),Coordinate(longitude:10,latitude:20+d),Coordinate(longitude:10,latitude:20)]
        let g = poly([ring])
        let center = Coordinate(longitude: 10 + d/2, latitude: 20 + d/2)
        #expect(Geometry.contains(center, in: g))
        // a clearly outside point should not become boundary due to fixed tolerance
        #expect(!Geometry.contains(Coordinate(longitude: 10 - 0.001, latitude: 20 - 0.001), in: g))
    }

    @Test func sharedEdgeAndHoleBoundaryDistanceUsesNearestEdge() {
        // point inside shell closer to hole edge than outer edge
        let shell = [Coordinate(longitude:0,latitude:0),Coordinate(longitude:10,latitude:0),Coordinate(longitude:10,latitude:10),Coordinate(longitude:0,latitude:10),Coordinate(longitude:0,latitude:0)]
        let hole = [Coordinate(longitude:4,latitude:4),Coordinate(longitude:4,latitude:6),Coordinate(longitude:6,latitude:6),Coordinate(longitude:6,latitude:4),Coordinate(longitude:4,latitude:4)]
        let g = poly([shell, hole])
        let p = Coordinate(longitude: 3.8, latitude: 5) // ~0.2 deg from hole left edge, far from shell
        let dist = Geometry.distanceToBoundary(p, in: g)
        // 0.2 degrees longitude at lat5 ~ 22km; but we just assert it's nearer hole edge than shell (~3.8deg~422km)
        #expect(dist < 25000)
    }
}
