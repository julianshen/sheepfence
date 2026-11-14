import Foundation

extension Geometry {
    static func contains(_ point: Coordinate, in geometry: RegionGeometry) -> Bool {
        for polygon in geometry.polygons {
            if containsPointInPolygonRings(point, rings: polygon.rings) { return true }
        }
        return false
    }
}
