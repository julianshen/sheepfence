import Foundation

enum GeometryValidator {
    private static let eps = 1e-12 // only for non-scale cases like antimeridian delta margin where absolute degrees intended

    static func validateAndBuild(
        featureID: String,
        geometry: Any,
        basePath: String
    ) throws -> (RegionGeometry, [RegionBounds]) {
        guard let g = geometry as? [String: Any] else {
            throw ImportDiagnostic.invalid(path: basePath, regionID: featureID, reason: "geometry must be an object")
        }
        guard let type = g["type"] as? String else {
            throw ImportDiagnostic.invalid(path: "\(basePath).type", regionID: featureID, reason: "geometry.type must be a string")
        }
        let coordsAny = g["coordinates"]
        let polygonRingsList: [[[[Any]]]]
        switch type {
        case "Polygon":
            guard let c = coordsAny as? [[[Any]]] else {
                throw ImportDiagnostic.invalid(path: "\(basePath).coordinates", regionID: featureID, reason: "Polygon coordinates must be an array of rings")
            }
            polygonRingsList = [c]
        case "MultiPolygon":
            guard let c = coordsAny as? [[[[Any]]]] else {
                throw ImportDiagnostic.invalid(path: "\(basePath).coordinates", regionID: featureID, reason: "MultiPolygon coordinates must be an array of polygons")
            }
            polygonRingsList = c
        default:
            throw ImportDiagnostic.invalid(path: "\(basePath).type", regionID: featureID, reason: "unsupported geometry type \(type)")
        }
        if polygonRingsList.isEmpty {
            throw ImportDiagnostic.invalid(path: "\(basePath).coordinates", regionID: featureID, reason: "geometry must contain at least one polygon")
        }
        var polygons: [Polygon] = []
        var bounds: [RegionBounds] = []
        for (pi, ringsRaw) in polygonRingsList.enumerated() {
            let ringsBasePath = type == "Polygon" ? "\(basePath).coordinates" : "\(basePath).coordinates[\(pi)]"
            let (poly, b) = try validatePolygon(ringsRaw, featureID: featureID, ringsBasePath: ringsBasePath)
            polygons.append(poly)
            bounds.append(b)
        }
        return (RegionGeometry(polygons: polygons), bounds)
    }

    private static func validatePolygon(_ ringsRaw: [[[Any]]], featureID: String, ringsBasePath: String) throws -> (Polygon, RegionBounds) {
        guard !ringsRaw.isEmpty else {
            throw ImportDiagnostic.invalid(path: ringsBasePath, regionID: featureID, reason: "polygon must have a shell ring")
        }
        var rings: [[Coordinate]] = []
        for (ri, ringRaw) in ringsRaw.enumerated() {
            let ringPath = "\(ringsBasePath)[\(ri)]"
            let ring = try parseAndValidateRing(ringRaw, featureID: featureID, path: ringPath)
            rings.append(ring)
        }
        let shell = rings[0]
        let shellOpen = Array(shell.dropLast())
        for i in 1..<rings.count {
            try validateHole(rings[i], shell: shell, holeIndex: i, featureID: featureID, ringsBasePath: ringsBasePath)
            for j in 1..<i {
                try validateHolePair(rings[j], rings[i], first: j, second: i, featureID: featureID, ringsBasePath: ringsBasePath)
            }
        }
        let normalized = rings.enumerated().map { idx, ring in normalizeWinding(ring, shouldBeCCW: idx == 0) }
        let xs = shellOpen.map(\.longitude)
        let ys = shellOpen.map(\.latitude)
        let b = RegionBounds(minLongitude: xs.min()!, minLatitude: ys.min()!, maxLongitude: xs.max()!, maxLatitude: ys.max()!)
        return (Polygon(rings: normalized), b)
    }

    /// Parses and validates a closed ring; returns closed ring (first == last).
    private static func parseAndValidateRing(_ raw: [[Any]], featureID: String, path: String) throws -> [Coordinate] {
        if raw.count < 4 {
            throw ImportDiagnostic.invalid(path: path, regionID: featureID, reason: "ring must contain at least 4 positions including closure")
        }
        var coords: [Coordinate] = []
        coords.reserveCapacity(raw.count)
        for (ci, pointRaw) in raw.enumerated() {
            let pPath = "\(path)[\(ci)]"
            guard pointRaw.count == 2 else {
                throw ImportDiagnostic.invalid(path: pPath, regionID: featureID, reason: "coordinate must be [longitude, latitude]")
            }
            guard let lon = number(pointRaw[0]), let lat = number(pointRaw[1]) else {
                throw ImportDiagnostic.invalid(path: pPath, regionID: featureID, reason: "coordinate values must be numbers")
            }
            guard lon.isFinite, lat.isFinite else {
                throw ImportDiagnostic.invalid(path: pPath, regionID: featureID, reason: "coordinates must be finite")
            }
            guard (-180.0...180.0).contains(lon), (-90.0...90.0).contains(lat) else {
                throw ImportDiagnostic.invalid(path: pPath, regionID: featureID, reason: "coordinate out of range")
            }
            coords.append(Coordinate(longitude: lon, latitude: lat))
        }
        // Spec requires closure by repeating first coordinate; strict equality.
        guard coords.first!.longitude == coords.last!.longitude && coords.first!.latitude == coords.last!.latitude else {
            throw ImportDiagnostic.invalid(path: path, regionID: featureID, reason: "ring must be closed")
        }
        for i in 0..<(coords.count - 1) {
            let dlon = abs(coords[i + 1].longitude - coords[i].longitude)
            if dlon > 180 + eps {
                throw ImportDiagnostic.invalid(path: "\(path)[\(i + 1)]", regionID: featureID, reason: "unsplit antimeridian crossing")
            }
        }
        let open = Array(coords.dropLast())
        let unique = distinctVertices(open)
        if unique.count < 3 || isCollinear(unique) {
            throw ImportDiagnostic.invalid(path: path, regionID: featureID, reason: "ring must have at least three distinct noncollinear vertices")
        }
        if hasSelfIntersection(open) {
            throw ImportDiagnostic.invalid(path: path, regionID: featureID, reason: "ring must not self-intersect or touch itself")
        }
        return coords
    }

    private static func validateHole(_ holeClosed: [Coordinate], shell shellClosed: [Coordinate], holeIndex: Int, featureID: String, ringsBasePath: String) throws {
        let hole = Array(holeClosed.dropLast())
        let shell = Array(shellClosed.dropLast())
        // No hole vertex outside shell; boundary contact rejected as touching.
        for (i, p) in hole.enumerated() {
            let cls = classifyPoint(p, ring: shell)
            if cls == .outside {
                throw ImportDiagnostic.invalid(path: "\(ringsBasePath)[\(holeIndex)][\(i)]", regionID: featureID, reason: "hole vertex outside shell")
            }
            if cls == .boundary {
                throw ImportDiagnostic.invalid(path: "\(ringsBasePath)[\(holeIndex)]", regionID: featureID, reason: "hole must not touch shell boundary")
            }
        }
        // Shell vertex strictly inside hole means hole not inside shell.
        for p in shell where classifyPoint(p, ring: hole) == .inside {
            throw ImportDiagnostic.invalid(path: "\(ringsBasePath)[\(holeIndex)]", regionID: featureID, reason: "hole must be inside shell")
        }
        if ringsTouchOrIntersect(hole, shell) {
            throw ImportDiagnostic.invalid(path: "\(ringsBasePath)[\(holeIndex)]", regionID: featureID, reason: "hole must not intersect or touch shell")
        }
    }

    private static func validateHolePair(_ aClosed: [Coordinate], _ bClosed: [Coordinate], first: Int, second: Int, featureID: String, ringsBasePath: String) throws {
        let a = Array(aClosed.dropLast())
        let b = Array(bClosed.dropLast())
        for p in a where classifyPoint(p, ring: b) != .outside {
            throw ImportDiagnostic.invalid(path: "\(ringsBasePath)[\(second)]", regionID: featureID, reason: "holes must not overlap or touch")
        }
        for p in b where classifyPoint(p, ring: a) != .outside {
            throw ImportDiagnostic.invalid(path: "\(ringsBasePath)[\(first)]", regionID: featureID, reason: "holes must not overlap or touch")
        }
        if ringsTouchOrIntersect(a, b) {
            throw ImportDiagnostic.invalid(path: "\(ringsBasePath)[\(second)]", regionID: featureID, reason: "holes must not overlap or touch")
        }
    }

    static func signedArea(_ ringClosed: [Coordinate]) -> Double {
        let ring = ringClosed.count > 1 ? Array(ringClosed.dropLast()) : ringClosed
        guard let o = ring.first else { return 0 }
        var area = 0.0
        for i in 0..<ring.count {
            let j = (i + 1) % ring.count
            let x1 = ring[i].longitude - o.longitude, y1 = ring[i].latitude - o.latitude
            let x2 = ring[j].longitude - o.longitude, y2 = ring[j].latitude - o.latitude
            area += x1 * y2 - x2 * y1
        }
        return area / 2.0
    }

    private static func normalizeWinding(_ ring: [Coordinate], shouldBeCCW: Bool) -> [Coordinate] {
        let isCCW = signedArea(ring) > 0
        if isCCW == shouldBeCCW { return ring }
        // Reverse closed ring preserving closure.
        let open = Array(ring.dropLast()).reversed()
        var out = Array(open)
        if let first = out.first { out.append(first) }
        return out
    }

    private static func isJSONBool(_ any: Any) -> Bool {
        if let n = any as? NSNumber { return CFGetTypeID(n) == CFBooleanGetTypeID() }
        return false
    }

    private static func number(_ any: Any) -> Double? {
        if isJSONBool(any) { return nil }
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return n.doubleValue
        }
        return nil
    }

    private static func samePoint(_ a: Coordinate, _ b: Coordinate) -> Bool {
        abs(a.longitude - b.longitude) <= eps && abs(a.latitude - b.latitude) <= eps
    }

    private static func distinctVertices(_ ring: [Coordinate]) -> [Coordinate] {
        var out: [Coordinate] = []
        for p in ring where out.last.map({ !samePoint($0, p) }) ?? true { out.append(p) }
        if out.count >= 2, samePoint(out.first!, out.last!) { out.removeLast() }
        return out
    }

    private static func orientTol(_ a: Coordinate, _ b: Coordinate, _ c: Coordinate) -> Double {
        let abx = b.longitude - a.longitude, aby = b.latitude - a.latitude
        let acx = c.longitude - a.longitude, acy = c.latitude - a.latitude
        let scale = max(abs(abx) + abs(aby), 1e-300) * max(abs(acx) + abs(acy), 1e-300)
        return 64 * Double.ulpOfOne * scale + 1e-18 * scale
    }

    private static func isCollinear(_ pts: [Coordinate]) -> Bool {
        guard pts.count >= 3 else { return true }
        let a = pts[0], b = pts[1]
        for p in pts.dropFirst(2) {
            if abs(cross(a, b, p)) > orientTol(a, b, p) { return false }
        }
        return true
    }

    private static func hasSelfIntersection(_ ring: [Coordinate]) -> Bool {
        let n = ring.count
        guard n >= 4 else { return false }
        for i in 0..<n {
            let a1 = ring[i], a2 = ring[(i + 1) % n]
            for j in (i + 1)..<n {
                if i == 0 && j == n - 1 { continue } // adjacent closing edge
                if j == i + 1 { continue }
                let b1 = ring[j], b2 = ring[(j + 1) % n]
                if segmentsIntersectOrTouch(a1, a2, b1, b2) { return true }
            }
        }
        return false
    }

    private static func ringsTouchOrIntersect(_ a: [Coordinate], _ b: [Coordinate]) -> Bool {
        for i in 0..<a.count {
            let a1 = a[i], a2 = a[(i + 1) % a.count]
            for j in 0..<b.count {
                let b1 = b[j], b2 = b[(j + 1) % b.count]
                if segmentsIntersectOrTouch(a1, a2, b1, b2) { return true }
            }
        }
        return false
    }

    private enum PointClass { case inside, boundary, outside }

    private static func classifyPoint(_ p: Coordinate, ring: [Coordinate]) -> PointClass {
        if pointOnRing(p, ring: ring) { return .boundary }
        return pointInRingRayCast(p, ring: ring) ? .inside : .outside
    }

    private static func pointOnRing(_ p: Coordinate, ring: [Coordinate]) -> Bool {
        for i in 0..<ring.count {
            let a = ring[i], b = ring[(i + 1) % ring.count]
            if pointOnSegment(p, a, b) { return true }
        }
        return false
    }

    // Geometry predicates (coordinate-linear, scale-aware)
    static func cross(_ a: Coordinate, _ b: Coordinate, _ c: Coordinate) -> Double {
        (b.longitude - a.longitude) * (c.latitude - a.latitude) - (b.latitude - a.latitude) * (c.longitude - a.longitude)
    }
    private static func orient(_ a: Coordinate, _ b: Coordinate, _ c: Coordinate) -> Int {
        let v = cross(a, b, c)
        if abs(v) <= orientTol(a, b, c) { return 0 }
        return v > 0 ? 1 : -1
    }
    private static func onSegmentCollinear(_ p: Coordinate, _ a: Coordinate, _ b: Coordinate) -> Bool {
        let minX = min(a.longitude, b.longitude), maxX = max(a.longitude, b.longitude)
        let minY = min(a.latitude, b.latitude), maxY = max(a.latitude, b.latitude)
        let dx = maxX - minX, dy = maxY - minY
        let tol = 64 * Double.ulpOfOne * max(dx + dy, 1e-300) + 1e-18 * (dx + dy + 1)
        return p.longitude >= minX - tol && p.longitude <= maxX + tol &&
            p.latitude >= minY - tol && p.latitude <= maxY + tol
    }
    static func pointOnSegment(_ p: Coordinate, _ a: Coordinate, _ b: Coordinate) -> Bool {
        orient(a, b, p) == 0 && onSegmentCollinear(p, a, b)
    }
    private static func segmentsIntersectOrTouch(_ a1: Coordinate, _ a2: Coordinate, _ b1: Coordinate, _ b2: Coordinate) -> Bool {
        let o1 = orient(a1, a2, b1), o2 = orient(a1, a2, b2)
        let o3 = orient(b1, b2, a1), o4 = orient(b1, b2, a2)
        if o1 != o2 && o3 != o4 { return true } // proper intersection
        if o1 == 0 && onSegmentCollinear(b1, a1, a2) { return true }
        if o2 == 0 && onSegmentCollinear(b2, a1, a2) { return true }
        if o3 == 0 && onSegmentCollinear(a1, b1, b2) { return true }
        if o4 == 0 && onSegmentCollinear(a2, b1, b2) { return true }
        return false
    }

    private static func pointInRingRayCast(_ p: Coordinate, ring: [Coordinate]) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let pi = ring[i], pj = ring[j]
            let intersects = ((pi.latitude > p.latitude) != (pj.latitude > p.latitude)) &&
                (p.longitude < (pj.longitude - pi.longitude) * (p.latitude - pi.latitude) / ((pj.latitude - pi.latitude) == 0 ? Double.leastNonzeroMagnitude : (pj.latitude - pi.latitude)) + pi.longitude)
            if intersects { inside.toggle() }
            j = i
        }
        return inside
    }
}
