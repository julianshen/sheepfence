import Foundation

enum CapacityFixtureFactory {
    static func make(overlapping: Bool, count: Int = 100, revision: Int = 1) throws -> Data {
        let features: [[String: Any]] = (0..<count).map { index in
            let cx = overlapping ? 10.0 : 10.0 + Double(index) * 0.05
            let radius = overlapping ? 0.01 + Double(index) * 0.00001 : 0.01
            var ring = (0..<100).map { vertex -> [Double] in
                let angle = 2 * Double.pi * Double(vertex) / 100
                return [cx + radius * cos(angle), 20 + radius * sin(angle)]
            }
            ring.append(ring[0])
            return ["type": "Feature", "id": String(format: "region-%03d", index),
                    "properties": ["priority": index],
                    "geometry": ["type": "Polygon", "coordinates": [ring]]]
        }
        return try JSONSerialization.data(withJSONObject: [
            "type": "FeatureCollection", "geofenceSchema": 1,
            "dataset": ["id": "capacity", "revision": revision, "generatedAt": "2026-11-14T00:00:00Z"],
            "features": features
        ], options: [.sortedKeys])
    }
}
