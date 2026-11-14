import Foundation
import Testing
@testable import SheepFence

@Suite struct DistanceGeometryTests {
    private func poly(_ rings: [[Coordinate]]) -> RegionGeometry { RegionGeometry(polygons: [Polygon(rings: rings)]) }
    private func rect(_ minLon: Double, _ minLat: Double, _ maxLon: Double, _ maxLat: Double) -> RegionGeometry {
        poly([[Coordinate(longitude:minLon,latitude:minLat), Coordinate(longitude:maxLon,latitude:minLat), Coordinate(longitude:maxLon,latitude:maxLat), Coordinate(longitude:minLon,latitude:maxLat), Coordinate(longitude:minLon,latitude:minLat)]])
    }
    private func meters(_ e: BoundaryDistanceEstimate) -> Double? {
        if case .approximateMeters(let m) = e { return m }
        return nil
    }

    @Test func interiorExteriorAndEdgeAnalytic() {
        let g = rect(10, 20, 10.01, 20.01)
        let inside = Coordinate(longitude: 10.002, latitude: 20.005)
        let m = meters(Geometry.boundaryDistanceEstimate(inside, in: g))
        #expect(m != nil && m! > 150 && m! < 300)
        let outside = Coordinate(longitude: 9.998, latitude: 20.005)
        let mo = meters(Geometry.boundaryDistanceEstimate(outside, in: g))
        #expect(mo != nil && mo! > 150 && mo! < 300)
        let onEdge = Geometry.boundaryDistanceEstimate(Coordinate(longitude: 10, latitude: 20.005), in: g)
        #expect(meters(onEdge) != nil && meters(onEdge)! <= 0.01)
    }

    @Test func supportedZeroDistinguishableFromUnsupported() {
        let g = rect(10, 20, 10.01, 20.01)
        let onEdge = Geometry.boundaryDistanceEstimate(Coordinate(longitude: 10, latitude: 20.005), in: g)
        if case .approximateMeters(let m) = onEdge { #expect(m == 0 || m < 1e-6) }
        else { Issue.record("expected supported zero on boundary") }
        let unsupported = Geometry.boundaryDistanceEstimate(Coordinate(longitude: 10, latitude: 81), in: g)
        #expect(unsupported == .unsupported(.outsideLocalModelRange))
        #expect(Geometry.distanceToBoundary(Coordinate(longitude: 10, latitude: 81), in: g) == 0)
    }

    @Test func holeInteriorUsesNearestHoleEdge() {
        // Entire geometry within 1° of query (supported envelope) but hole edge nearest.
        let shell = [Coordinate(longitude:0,latitude:0),Coordinate(longitude:0.008,latitude:0),Coordinate(longitude:0.008,latitude:0.008),Coordinate(longitude:0,latitude:0.008),Coordinate(longitude:0,latitude:0)]
        let hole = [Coordinate(longitude:0.003,latitude:0.003),Coordinate(longitude:0.003,latitude:0.005),Coordinate(longitude:0.005,latitude:0.005),Coordinate(longitude:0.005,latitude:0.003),Coordinate(longitude:0.003,latitude:0.003)]
        let g = poly([shell, hole])
        let inHole = Geometry.boundaryDistanceEstimate(Coordinate(longitude: 0.004, latitude: 0.0035), in: g)
        let m = meters(inHole)
        #expect(m != nil && m! > 40 && m! < 70) // ~0.0005 deg lat from hole bottom edge
        let onHole = Geometry.boundaryDistanceEstimate(Coordinate(longitude: 0.003, latitude: 0.004), in: g)
        #expect(meters(onHole) != nil && meters(onHole)! <= 0.01)
    }

    @Test func multiComponentUsesNearestBoundary() {
        let g = RegionGeometry(polygons: [
            Polygon(rings: [[Coordinate(longitude:0,latitude:0),Coordinate(longitude:0.002,latitude:0),Coordinate(longitude:0.002,latitude:0.002),Coordinate(longitude:0,latitude:0.002),Coordinate(longitude:0,latitude:0)]]),
            Polygon(rings: [[Coordinate(longitude:0.004,latitude:0),Coordinate(longitude:0.006,latitude:0),Coordinate(longitude:0.006,latitude:0.002),Coordinate(longitude:0.004,latitude:0.002),Coordinate(longitude:0.004,latitude:0)]])
        ])
        let p = Coordinate(longitude: 0.003, latitude: 0.001)
        let m = meters(Geometry.boundaryDistanceEstimate(p, in: g))
        #expect(m != nil && m! > 80 && m! < 140) // ~0.001 deg from each component
    }

    @Test func datelineLocalEnvelopeSupported() {
        let ring = [Coordinate(longitude:179.999,latitude:0),Coordinate(longitude:179.9995,latitude:0),Coordinate(longitude:179.9995,latitude:0.001),Coordinate(longitude:179.999,latitude:0.001),Coordinate(longitude:179.999,latitude:0)]
        let g = poly([ring])
        let p = Coordinate(longitude: -179.9992, latitude: 0.0005)
        let e = Geometry.boundaryDistanceEstimate(p, in: g)
        let m = meters(e)
        #expect(m != nil && m! < 200)
        #expect(Geometry.distanceToBoundary(p, in: g) < 200)
    }

    @Test func unsupportedEnvelopeCases() {
        let g = rect(10, 20, 10.01, 20.01)
        #expect(Geometry.boundaryDistanceEstimate(Coordinate(longitude: 10, latitude: 80.1), in: g) == .unsupported(.outsideLocalModelRange))
        #expect(Geometry.boundaryDistanceEstimate(Coordinate(longitude: 12, latitude: 20.005), in: g) == .unsupported(.outsideLocalModelRange)) // vertex >1° away
        let far = RegionGeometry(polygons: [Polygon(rings: [[Coordinate(longitude:20,latitude:20),Coordinate(longitude:21,latitude:20),Coordinate(longitude:21,latitude:21),Coordinate(longitude:20,latitude:21),Coordinate(longitude:20,latitude:20)]])])
        #expect(Geometry.boundaryDistanceEstimate(Coordinate(longitude: 10.005, latitude: 20.005), in: far) == .unsupported(.outsideLocalModelRange))
        #expect(Geometry.distanceToBoundary(Coordinate(longitude: 12, latitude: 20.005), in: g) == 0)
    }

    @Test func adapterPreservesConservativeBehavior() {
        let g = rect(10, 20, 10.01, 20.01)
        let supported = Geometry.boundaryDistanceEstimate(Coordinate(longitude: 10.002, latitude: 20.005), in: g)
        if case .approximateMeters(let m) = supported {
            #expect(Geometry.distanceToBoundary(Coordinate(longitude: 10.002, latitude: 20.005), in: g) == m)
        } else { Issue.record("expected supported") }
        #expect(Geometry.distanceToBoundary(Coordinate(longitude: 10, latitude: 81), in: g) == 0)
    }
}
