import Foundation
import CryptoKit

enum GeoJSONDecoder {
    static func decode(_ data: Data) throws -> ValidatedSnapshot {
        let json: Any
        do { json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { throw ImportDiagnostic.invalid(path: "$", reason: "invalid JSON: \(error.localizedDescription)") }

        guard let root = json as? [String: Any] else {
            throw ImportDiagnostic.invalid(path: "$", reason: "root must be an object")
        }
        guard (root["type"] as? String) == "FeatureCollection" else {
            throw ImportDiagnostic.invalid(path: "$.type", reason: "root type must be FeatureCollection")
        }

        // schema
        guard let schemaAny = root["geofenceSchema"], let schema = intValue(schemaAny) else {
            throw ImportDiagnostic.invalid(path: "$.geofenceSchema", reason: "geofenceSchema must be an integer")
        }
        if schema != 1 { throw GeofenceError.unsupportedSchema(schema) }

        // dataset
        guard let datasetAny = root["dataset"] as? [String: Any] else {
            throw ImportDiagnostic.invalid(path: "$.dataset", reason: "dataset must be an object")
        }
        guard let datasetID = datasetAny["id"] as? String, !datasetID.isEmpty else {
            throw ImportDiagnostic.invalid(path: "$.dataset.id", reason: "dataset.id must be a non-empty string")
        }
        guard let revAny = datasetAny["revision"], let revision = intValue(revAny), revision > 0 else {
            throw ImportDiagnostic.invalid(path: "$.dataset.revision", reason: "dataset.revision must be a positive integer")
        }
        guard let gen = datasetAny["generatedAt"] as? String else {
            throw ImportDiagnostic.invalid(path: "$.dataset.generatedAt", reason: "dataset.generatedAt must be a string")
        }
        guard let generatedAt = parseRFC3339UTC(gen) else {
            throw ImportDiagnostic.invalid(path: "$.dataset.generatedAt", reason: "generatedAt must be RFC3339 UTC ending with Z")
        }

        // features
        guard let featuresAny = root["features"] as? [[String: Any]] else {
            if root["features"] == nil { throw ImportDiagnostic.invalid(path: "$.features", reason: "features is required") }
            throw ImportDiagnostic.invalid(path: "$.features", reason: "features must be an array")
        }

        var seen = Set<String>()
        var regions: [Region] = []
        regions.reserveCapacity(featuresAny.count)
        for (i, f) in featuresAny.enumerated() {
            let fPath = "$.features[\(i)]"
            guard (f["type"] as? String) == "Feature" else {
                throw ImportDiagnostic.invalid(path: "\(fPath).type", reason: "feature type must be Feature")
            }
            guard let fid = f["id"] as? String, !fid.isEmpty else {
                throw ImportDiagnostic.invalid(path: "\(fPath).id", reason: "Feature.id must be a non-empty string")
            }
            if seen.contains(fid) {
                throw ImportDiagnostic.invalid(path: "\(fPath).id", regionID: fid, reason: "duplicate feature id")
            }
            seen.insert(fid)
            let props = try parseProperties(f["properties"], path: "\(fPath).properties", featureID: fid)
            guard let geomAny = f["geometry"] else {
                throw ImportDiagnostic.invalid(path: "\(fPath).geometry", regionID: fid, reason: "geometry is required")
            }
            let (geometry, bounds) = try GeometryValidator.validateAndBuild(featureID: fid, geometry: geomAny, basePath: "\(fPath).geometry")
            let name = props.name ?? fid
            regions.append(Region(id: RegionID(datasetID: datasetID, featureID: fid), name: name, enabled: props.enabled, priority: props.priority, geometry: geometry, bounds: bounds))
        }

        let metadata = DatasetMetadata(id: datasetID, revision: revision, generatedAt: generatedAt)
        let hash = Data(SHA256.hash(data: data))
        return ValidatedSnapshot(metadata: metadata, sourceBytes: data, sha256: hash, regions: regions)
    }

    private struct Props { let name: String?; let enabled: Bool; let priority: Int }
    private static func parseProperties(_ any: Any?, path: String, featureID: String) throws -> Props {
        guard let any else {
            throw ImportDiagnostic.invalid(path: path, regionID: featureID, reason: "properties must be an object")
        }
        guard let obj = any as? [String: Any] else {
            throw ImportDiagnostic.invalid(path: path, regionID: featureID, reason: "properties must be an object")
        }
        var name: String? = nil
        if let n = obj["name"] {
            guard let s = n as? String else { throw ImportDiagnostic.invalid(path: "\(path).name", regionID: featureID, reason: "name must be a string") }
            name = s
        }
        var enabled = true
        if let e = obj["enabled"] {
            guard isJSONBool(e), let b = e as? Bool else {
                throw ImportDiagnostic.invalid(path: "\(path).enabled", regionID: featureID, reason: "enabled must be a boolean")
            }
            enabled = b
        }
        var priority = 0
        if let p = obj["priority"] {
            guard let i = intValue(p) else { throw ImportDiagnostic.invalid(path: "\(path).priority", regionID: featureID, reason: "priority must be an integer") }
            priority = i
        }
        return Props(name: name, enabled: enabled, priority: priority)
    }

    private static func isJSONBool(_ any: Any) -> Bool {
        if let n = any as? NSNumber { return CFGetTypeID(n) == CFBooleanGetTypeID() }
        return false
    }

    private static func intValue(_ any: Any) -> Int? {
        if isJSONBool(any) { return nil }
        if let i = any as? Int { return i }
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            // exact integer conversion
            let i64 = n.int64Value
            guard NSNumber(value: i64).compare(n) == .orderedSame else { return nil }
            return Int(exactly: i64)
        }
        return nil
    }

    private static func parseRFC3339UTC(_ s: String) -> Date? {
        guard s.hasSuffix("Z") else { return nil }
        guard isLikelyRFC3339UTC(s) else { return nil }
        let withFraction = s.contains(".")
        let f = ISO8601DateFormatter()
        f.formatOptions = withFraction ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        guard let d = f.date(from: s) else { return nil }
        // Strict calendar validation: reject normalized invalid dates like 2026-02-30.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = cal.dateComponents(in: cal.timeZone, from: d)
        guard let y = year(from: s), let m = month(from: s), let day = day(from: s),
              let hh = hour(from: s), let mm = minute(from: s), let ss = second(from: s) else { return nil }
        guard comps.year == y, comps.month == m, comps.day == day,
              comps.hour == hh, comps.minute == mm, comps.second == ss else { return nil }
        return d
    }

    private static func isLikelyRFC3339UTC(_ s: String) -> Bool {
        // YYYY-MM-DDTHH:MM:SS(.frac)?Z
        let base = Array(s)
        if base.count < 20 { return false }
        func isDigit(_ i: Int) -> Bool { base[i] >= "0" && base[i] <= "9" }
        let checks = [0,1,2,3,5,6,8,9,11,12,14,15,17,18]
        if !checks.allSatisfy(isDigit) { return false }
        if base[4] != "-" || base[7] != "-" || base[10] != "T" || base[13] != ":" || base[16] != ":" { return false }
        if base[19] == "." {
            guard base.last == "Z", base.count >= 21 else { return false }
            for i in 20..<(base.count - 1) where !isDigit(i) { return false }
            return true
        }
        return base.count == 20 && base[19] == "Z"
    }
    private static func intPart(_ s: String, _ start: Int, _ len: Int) -> Int? { Int(s.dropFirst(start).prefix(len)) }
    private static func year(from s: String) -> Int? { intPart(s, 0, 4) }
    private static func month(from s: String) -> Int? { intPart(s, 5, 2) }
    private static func day(from s: String) -> Int? { intPart(s, 8, 2) }
    private static func hour(from s: String) -> Int? { intPart(s, 11, 2) }
    private static func minute(from s: String) -> Int? { intPart(s, 14, 2) }
    private static func second(from s: String) -> Int? { intPart(s, 17, 2) }
}
