import Foundation

enum Geometry {
    // Scale-aware predicates: tolerances proportional to coordinate magnitudes/deltas (no fixed min area).
    static func cross(_ a: Coordinate, _ b: Coordinate, _ c: Coordinate) -> Double {
        (b.longitude - a.longitude) * (c.latitude - a.latitude) - (b.latitude - a.latitude) * (c.longitude - a.longitude)
    }

    private static func orientTol(_ a: Coordinate, _ b: Coordinate, _ c: Coordinate) -> Double {
        let abx = b.longitude - a.longitude, aby = b.latitude - a.latitude
        let acx = c.longitude - a.longitude, acy = c.latitude - a.latitude
        let scale = max(abs(abx) + abs(aby), 1e-300) * max(abs(acx) + abs(acy), 1e-300)
        return 64 * Double.ulpOfOne * scale + 1e-18 * scale
    }

    static func orientation(_ a: Coordinate, _ b: Coordinate, _ c: Coordinate) -> Int {
        let v = cross(a, b, c)
        if abs(v) <= orientTol(a, b, c) { return 0 }
        return v > 0 ? 1 : -1
    }

    static func onSegmentCollinear(_ p: Coordinate, _ a: Coordinate, _ b: Coordinate) -> Bool {
        let minX = min(a.longitude, b.longitude), maxX = max(a.longitude, b.longitude)
        let minY = min(a.latitude, b.latitude), maxY = max(a.latitude, b.latitude)
        let dx = maxX - minX, dy = maxY - minY
        let tol = 64 * Double.ulpOfOne * max(dx + dy, 1e-300) + 1e-18 * (dx + dy + 1)
        return p.longitude >= minX - tol && p.longitude <= maxX + tol &&
               p.latitude >= minY - tol && p.latitude <= maxY + tol
    }

    static func pointOnSegment(_ p: Coordinate, _ a: Coordinate, _ b: Coordinate) -> Bool {
        orientation(a, b, p) == 0 && onSegmentCollinear(p, a, b)
    }

    static func openRing(_ ring: [Coordinate]) -> [Coordinate] {
        guard ring.count >= 2 else { return ring }
        if ring.first!.longitude == ring.last!.longitude && ring.first!.latitude == ring.last!.latitude {
            return Array(ring.dropLast())
        }
        return ring
    }

    static func pointOnRingBoundary(_ p: Coordinate, ring: [Coordinate]) -> Bool {
        let r = openRing(ring)
        guard r.count >= 2 else { return false }
        for i in 0..<r.count {
            if pointOnSegment(p, r[i], r[(i + 1) % r.count]) { return true }
        }
        return false
    }

    /// Ray-casting; boundary must be checked separately.
    static func pointStrictlyInsideRing(_ p: Coordinate, ring: [Coordinate]) -> Bool {
        let r = openRing(ring)
        var inside = false
        var j = r.count - 1
        for i in 0..<r.count {
            let pi = r[i], pj = r[j]
            let dy = pj.latitude - pi.latitude
            if (pi.latitude > p.latitude) != (pj.latitude > p.latitude), abs(dy) > 0 {
                let xInt = (pj.longitude - pi.longitude) * (p.latitude - pi.latitude) / dy + pi.longitude
                // scale-aware comparison
                let tol = 64 * Double.ulpOfOne * max(abs(xInt), abs(p.longitude), 1) + 1e-18
                if p.longitude < xInt - tol { inside.toggle() }
                else if abs(p.longitude - xInt) <= tol {
                    // On edge in x at intersection: treat as boundary-like uncertainty not inside toggle instability;
                    // caller checks boundary first, so this rare numeric case is conservative by not toggling.
                } else {
                    // p.longitude > xInt
                }
            }
            j = i
        }
        return inside
    }

    static func containsPointInPolygonRings(_ point: Coordinate, rings: [[Coordinate]]) -> Bool {
        guard let shell = rings.first else { return false }
        let shellOpen = openRing(shell)
        // Pure GeoJSON coordinate-linear containment in raw coordinates (preserves wide valid polygons).
        if containsInRawSpace(point, shell: shellOpen, holes: rings.dropFirst().map { openRing($0) }) {
            return true
        }
        // Periodic copy for split components near dateline (e.g. +179.999 region vs -179.999 query),
        // checked as whole consistent translated polygons without mutating raw interior semantics.
        if containsInPeriodicCopy(point, shell: shellOpen, holes: rings.dropFirst().map { openRing($0) }) {
            return true
        }
        return false
    }

    private static func containsInRawSpace(_ point: Coordinate, shell: [Coordinate], holes: [[Coordinate]]) -> Bool {
        if pointOnRingBoundary(point, ring: shell) { return true }
        guard pointStrictlyInsideRing(point, ring: shell) else { return false }
        for hole in holes {
            if pointOnRingBoundary(point, ring: hole) { return true }
            if pointStrictlyInsideRing(point, ring: hole) { return false }
        }
        return true
    }

    private static func containsInPeriodicCopy(_ point: Coordinate, shell: [Coordinate], holes: [[Coordinate]]) -> Bool {
        let centerLon = ringCenterLongitude(shell)
        let candidates = [point.longitude, point.longitude + 360, point.longitude - 360, centerLon, centerLon + 360, centerLon - 360]
        var tried: Set<Int> = []
        for c in candidates {
            let q = Int((c / 360.0).rounded())
            if tried.contains(q) { continue }
            tried.insert(q)
            let shift = Double(q) * 360.0
            let up = Coordinate(longitude: point.longitude + shift, latitude: point.latitude)
            let shiftedShell = shell.map { Coordinate(longitude: $0.longitude, latitude: $0.latitude) }
            // Evaluate using point shifted into shell neighborhood via unwrap-around reference; to keep polygon
            // geometry consistent, unwrap shell/hole points continuously from shell first vertex reference.
            let ref = shiftedShell.first?.longitude ?? centerLon
            let uShell = unwrapRingContinuously(shiftedShell, referenceLongitude: ref)
            if pointOnRingBoundary(up, ring: uShell) { return true }
            if pointStrictlyInsideRing(up, ring: uShell) {
                var inHole = false
                for hole in holes {
                    let hRef = hole.first?.longitude ?? ref
                    let uHole = unwrapRingContinuously(hole, referenceLongitude: hRef)
                    if pointOnRingBoundary(up, ring: uHole) || pointStrictlyInsideRing(up, ring: uHole) { inHole = true; break }
                }
                if !inHole { return true }
            }
            // also try unwrapping relative to up longitude for near-dateline split copies
            let uShell2 = unwrapRingContinuously(shiftedShell, referenceLongitude: up.longitude)
            if pointOnRingBoundary(up, ring: uShell2) { return true }
            if pointStrictlyInsideRing(up, ring: uShell2) {
                var inHole = false
                for hole in holes {
                    let uHole = unwrapRingContinuously(hole, referenceLongitude: up.longitude)
                    if pointOnRingBoundary(up, ring: uHole) || pointStrictlyInsideRing(up, ring: uHole) { inHole = true; break }
                }
                if !inHole { return true }
            }
        }
        return false
    }

    private static func ringCenterLongitude(_ ring: [Coordinate]) -> Double {
        guard !ring.isEmpty else { return 0 }
        let xs = ring.map(\.longitude)
        return ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2
    }

    private static func unwrapRingContinuously(_ ring: [Coordinate], referenceLongitude ref: Double) -> [Coordinate] {
        guard let first = ring.first else { return ring }
        var out: [Coordinate] = []
        out.reserveCapacity(ring.count)
        var prevLon = normalizeLongitudeNear(first.longitude, reference: ref)
        out.append(Coordinate(longitude: prevLon, latitude: first.latitude))
        for c in ring.dropFirst() {
            let lon = prevLon + normalizeLongitudeDelta(c.longitude - prevLon)
            out.append(Coordinate(longitude: lon, latitude: c.latitude))
            prevLon = lon
        }
        return out
    }

    // Periodic longitude helpers
    static func normalizeLongitudeDelta(_ d: Double) -> Double {
        var x = d
        while x > 180 { x -= 360 }
        while x < -180 { x += 360 }
        return x
    }
    static func normalizeLongitudeNear(_ lon: Double, reference: Double) -> Double {
        reference + normalizeLongitudeDelta(lon - reference)
    }
    static func unwrapRing(_ ring: [Coordinate], nearLongitude ref: Double) -> [Coordinate] {
        unwrapRingContinuously(ring, referenceLongitude: ref)
    }

    // Local meter projection (equirectangular around reference latitude), conservative for distance estimates.
    static let metersPerDegreeLatitude = 111_132.0
    static func metersPerDegreeLongitude(at latitude: Double) -> Double {
        let clamped = min(89.999, max(-89.999, latitude))
        let c = cos(clamped * .pi / 180.0)
        return 111_320.0 * max(0.0001, abs(c))
    }
    static func toLocalMeters(_ c: Coordinate, refLat: Double, lonScaleAt refLon: Double? = nil) -> (x: Double, y: Double) {
        let mLon = metersPerDegreeLongitude(at: refLon.map { _ in refLat } ?? refLat)
        return (x: c.longitude * mLon, y: c.latitude * metersPerDegreeLatitude)
    }
}
