import Foundation
import Testing

/// Checks fixture packaging only. Production importer acceptance tests come later.
@Test func specFixtureIsBundled() throws {
    let url = try #require(Bundle.module.url(forResource: "campus-v3", withExtension: "geojson"))
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    let root = try #require(object as? [String: Any])
    #expect(root["geofenceSchema"] as? Int == 1)
    let dataset = try #require(root["dataset"] as? [String: Any])
    #expect(dataset["revision"] as? Int == 3)
    let features = try #require(root["features"] as? [[String: Any]])
    #expect(features.compactMap { $0["id"] as? String } == ["campus", "garden"])
}
