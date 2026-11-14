import Foundation

public struct Coordinate: Hashable, Codable, Sendable {
    public let longitude: Double
    public let latitude: Double
    public init(longitude: Double, latitude: Double) { self.longitude = longitude; self.latitude = latitude }
    public var isValid: Bool { longitude.isFinite && latitude.isFinite && (-180...180).contains(longitude) && (-90...90).contains(latitude) }
}

struct Polygon: Equatable, Codable, Sendable {
    /// Closed rings, shell first, followed by holes. Winding does not determine role.
    let rings: [[Coordinate]]
}
struct RegionGeometry: Equatable, Codable, Sendable { let polygons: [Polygon] }
struct RegionBounds: Equatable, Codable, Sendable {
    let minLongitude: Double
    let minLatitude: Double
    let maxLongitude: Double
    let maxLatitude: Double
}
struct Region: Equatable, Codable, Sendable {
    let id: RegionID
    let name: String
    let enabled: Bool
    let priority: Int
    let geometry: RegionGeometry
    /// One rectangle per polygon, avoiding a world-spanning box for split dateline data.
    let bounds: [RegionBounds]
}
public struct GeometryQueryResult: Equatable, Sendable {
    public let regionID: RegionID
    public let revision: Int
    public let membership: Membership
    public init(regionID: RegionID, revision: Int, membership: Membership) {
        self.regionID = regionID; self.revision = revision; self.membership = membership
    }
}
