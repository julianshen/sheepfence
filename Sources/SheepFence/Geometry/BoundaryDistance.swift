import Foundation

extension Geometry {
    /// Explicit boundary-distance estimate in local meters.
    /// Coordinate-linear edges mapped via local equirectangular projection at point latitude.
    /// Longitudes unwrapped relative to point for periodic correctness (split dateline components).
    ///
    /// Support envelope (neighborhood-scale): |point latitude| <= 80° and every ring vertex within
    /// 1° latitude and 1° unwrapped longitude of the query point. Outside this envelope, or for
    /// invalid/unsupported mapping, returns `.unsupported(.outsideLocalModelRange)`. Non-finite
    /// numerical results return `.unsupported(.numericalFailure)`. This is an approximate local-meter
    /// model, not rigorous global geodesic correctness.
    static func boundaryDistanceEstimate(_ point: Coordinate, in geometry: RegionGeometry) -> BoundaryDistanceEstimate {
        let maxSupportedAbsLatitude = 80.0
        let maxLocalExtentDegrees = 1.0
        var best = Double.infinity
        let refLat = point.latitude
        guard refLat.isFinite, point.longitude.isFinite,
              abs(refLat) <= maxSupportedAbsLatitude else { return .unsupported(.outsideLocalModelRange) }
        let mLon = metersPerDegreeLongitude(at: refLat)
        guard mLon.isFinite, mLon > 0, metersPerDegreeLatitude.isFinite else { return .unsupported(.numericalFailure) }
        let pLon = point.longitude
        let pLat = point.latitude
        let p = (x: 0.0, y: pLat * metersPerDegreeLatitude)

        func localPoint(for c: Coordinate, previousLon: inout Double?, isFirst: Bool) -> (x: Double, y: Double)? {
            guard c.latitude.isFinite, c.longitude.isFinite else { return nil }
            guard abs(c.latitude - pLat) <= maxLocalExtentDegrees else { return nil }
            let lon: Double
            if isFirst {
                lon = normalizeLongitudeNear(c.longitude, reference: pLon)
            } else {
                lon = (previousLon ?? pLon) + normalizeLongitudeDelta(c.longitude - (previousLon ?? pLon))
            }
            let dLon = normalizeLongitudeDelta(lon - pLon)
            guard abs(dLon) <= maxLocalExtentDegrees else { return nil }
            previousLon = lon
            return (x: dLon * mLon, y: c.latitude * metersPerDegreeLatitude)
        }

        var hasSegment = false
        for polygon in geometry.polygons {
            for ring in polygon.rings {
                let r = openRing(ring)
                guard r.count >= 2 else { continue }
                var prevLon: Double? = nil
                guard let firstPt = localPoint(for: r[0], previousLon: &prevLon, isFirst: true) else {
                    return .unsupported(.outsideLocalModelRange)
                }
                var prev = firstPt
                for idx in 1..<r.count {
                    guard let cur = localPoint(for: r[idx], previousLon: &prevLon, isFirst: false) else {
                        return .unsupported(.outsideLocalModelRange)
                    }
                    let d = distancePointToSegment(p, prev, cur)
                    guard d.isFinite, d >= 0 else { return .unsupported(.numericalFailure) }
                    hasSegment = true
                    if d < best { best = d }
                    prev = cur
                }
                let dClose = distancePointToSegment(p, prev, firstPt)
                guard dClose.isFinite, dClose >= 0 else { return .unsupported(.numericalFailure) }
                hasSegment = true
                if dClose < best { best = dClose }
            }
        }
        guard hasSegment, best.isFinite, best >= 0 else { return .unsupported(.numericalFailure) }
        return .approximateMeters(best)
    }

    /// Conservative adapter: returns 0 for unsupported distance (never overstates separation).
    /// Callers needing explicit unsupported-vs-supported-zero must use `boundaryDistanceEstimate`.
    static func distanceToBoundary(_ point: Coordinate, in geometry: RegionGeometry) -> Double {
        switch boundaryDistanceEstimate(point, in: geometry) {
        case .approximateMeters(let meters): return meters
        case .unsupported: return 0
        }
    }

    private static func distancePointToSegment(_ p: (x: Double, y: Double), _ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
        let abx = b.x - a.x, aby = b.y - a.y
        let apx = p.x - a.x, apy = p.y - a.y
        let ab2 = abx * abx + aby * aby
        if ab2 <= 0 { return hypot(apx, apy) }
        var t = (apx * abx + apy * aby) / ab2
        if t < 0 { t = 0 } else if t > 1 { t = 1 }
        let qx = a.x + t * abx, qy = a.y + t * aby
        return hypot(p.x - qx, p.y - qy)
    }
}
