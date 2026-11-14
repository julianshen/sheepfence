import Foundation

enum GeometryBounds {
    static func polygonBounds(_ polygon: Polygon) -> RegionBounds? {
        guard let shell = polygon.rings.first, !shell.isEmpty else { return nil }
        let xs = shell.map(\.longitude)
        let ys = shell.map(\.latitude)
        return RegionBounds(minLongitude: xs.min()!, minLatitude: ys.min()!, maxLongitude: xs.max()!, maxLatitude: ys.max()!)
    }
}

extension Geometry {
    /// Conservative bbox prefilter. True whenever uncertain or mapping unsupported.
    /// A false result means the point+radius cannot intersect any bound under this local meter model.
    static func isCandidate(_ point: Coordinate, radiusMeters: Double, bounds: [RegionBounds]) -> Bool {
        guard point.longitude.isFinite, point.latitude.isFinite, radiusMeters.isFinite, radiusMeters >= 0 else {
            return true
        }
        // Unsupported/uncertain mapping near high latitudes: remain conservative.
        if abs(point.latitude) > 85.0 { return true }
        let mPerDegLon = metersPerDegreeLongitude(at: point.latitude)
        guard mPerDegLon.isFinite, mPerDegLon > 0.1 else { return true }
        let lonMargin = radiusMeters / mPerDegLon
        let latMargin = radiusMeters / metersPerDegreeLatitude
        guard lonMargin.isFinite, latMargin.isFinite else { return true }
        // If margin spans world or cannot be reasoned simply, conservative.
        if lonMargin >= 180 { return true }

        let pLat = point.latitude
        let pLon = point.longitude

        func lonIntervalIntersects(_ b: RegionBounds) -> Bool {
            let bMin = b.minLongitude, bMax = b.maxLongitude
            let width = bMax - bMin
            if width > 360 { return true }
            // Try to place bound interval near point by shifting by 360k.
            // Candidate if distance in periodic longitude from pLon to [bMin,bMax] <= lonMargin.
            let base = bMin
            let k = ((pLon - base) / 360.0).rounded(.toNearestOrAwayFromZero)
            for shift in [k - 1, k, k + 1] {
                let s = shift * 360.0
                let minS = bMin + s - lonMargin
                let maxS = bMax + s + lonMargin
                if pLon >= minS && pLon <= maxS { return true }
            }
            return false
        }

        for b in bounds {
            if pLat < b.minLatitude - latMargin { continue }
            if pLat > b.maxLatitude + latMargin { continue }
            // Bound latitude plausibly large-span? conservative.
            if b.maxLatitude - b.minLatitude > 170 { return true }
            if lonIntervalIntersects(b) { return true }
        }
        return false
    }
}
