import Foundation
import Testing
@testable import SheepFence

@Suite struct ImportTests {
    private func fixtureData(_ name: String) throws -> Data {
        let bundle = Bundle.module
        let url = bundle.url(forResource: name, withExtension: "geojson", subdirectory: "Geometry")
            ?? bundle.url(forResource: name, withExtension: "geojson")
            ?? bundle.urls(forResourcesWithExtension: "geojson", subdirectory: nil)?.first(where: { $0.deletingPathExtension().lastPathComponent == name })
        let resolved = try #require(url, "fixture \(name).geojson not found in bundle")
        return try Data(contentsOf: resolved)
    }
    private func decodeFixture(_ name: String) throws -> ValidatedSnapshot {
        try GeoJSONDecoder.decode(try fixtureData(name))
    }
    private func expectInvalid(_ name: String, path: String? = nil, regionID: String? = nil, reasonContains: String? = nil, sourceLocation: SourceLocation = #_sourceLocation) throws {
        do {
            _ = try decodeFixture(name)
            Issue.record("expected invalid snapshot \(name)", sourceLocation: sourceLocation)
        } catch let GeofenceError.invalidSnapshot(r, p, reason) {
            if let regionID { #expect(r == regionID, "regionID", sourceLocation: sourceLocation) }
            if let path { #expect(p == path, "path", sourceLocation: sourceLocation) }
            if let reasonContains { #expect(reason.contains(reasonContains), "reason \(reason)", sourceLocation: sourceLocation) }
        } catch {
            Issue.record("unexpected error \(error)", sourceLocation: sourceLocation)
        }
    }
    private func decodeJSON(_ json: String) throws -> ValidatedSnapshot { try GeoJSONDecoder.decode(Data(json.utf8)) }

    @Test func validFixtureAcceptedWithDefaultsNormalizationAndBytes() throws {
        let data = try fixtureData("valid-normalized")
        let snap = try GeoJSONDecoder.decode(data)
        #expect(snap.metadata.id == "com.example.test")
        #expect(snap.metadata.revision == 1)
        #expect(snap.sourceBytes == data)
        #expect(snap.sha256.count == 32)
        #expect(snap.regions.map(\.id.featureID) == ["poly", "multi"])
        let poly = try #require(snap.regions.first { $0.id.featureID == "poly" })
        #expect(poly.name == "Poly")
        #expect(poly.enabled == true)
        #expect(poly.priority == 2)
        #expect(poly.geometry.polygons.count == 1)
        #expect(poly.geometry.polygons[0].rings.count == 2)
        #expect(poly.bounds.count == 1)
        // shell normalized to CCW, hole to CW (signed area)
        #expect(GeometryValidator.signedArea(poly.geometry.polygons[0].rings[0]) > 0)
        #expect(GeometryValidator.signedArea(poly.geometry.polygons[0].rings[1]) < 0)
        // closed rings preserved
        #expect(poly.geometry.polygons[0].rings[0].first == poly.geometry.polygons[0].rings[0].last)
        let multi = try #require(snap.regions.first { $0.id.featureID == "multi" })
        #expect(multi.name == "multi") // default name = id
        #expect(multi.enabled == true)
        #expect(multi.priority == 0)
        #expect(multi.geometry.polygons.count == 2)
        #expect(multi.bounds.count == 2)
    }

    @Test func acceptsReversedWindingAndFractionalZTimestamp() throws {
        let snap = try decodeFixture("valid-reversed-winding")
        #expect(snap.metadata.revision == 2)
        let r = try #require(snap.regions.first)
        #expect(r.priority == -1)
        #expect(GeometryValidator.signedArea(r.geometry.polygons[0].rings[0]) > 0)
        #expect(GeometryValidator.signedArea(r.geometry.polygons[0].rings[1]) < 0)
        #expect(r.geometry.polygons[0].rings[0].first == r.geometry.polygons[0].rings[0].last)
    }

    @Test func acceptsEmptyFeatures() throws {
        let snap = try decodeJSON(#"{"type":"FeatureCollection","geofenceSchema":1,"dataset":{"id":"d","revision":1,"generatedAt":"2026-11-12T00:00:00Z"},"features":[]}"#)
        #expect(snap.regions.isEmpty)
        #expect(snap.metadata.id == "d")
    }

    @Test func rejectsUnsupportedSchemaAndWrongTypes() throws {
        do { _ = try decodeFixture("invalid-unsupported-schema"); Issue.record("expected unsupported schema") }
        catch GeofenceError.unsupportedSchema(let v) { #expect(v == 2) }
        catch { Issue.record("unexpected \(error)") }
        try expectInvalidJSON(#"{"type":"FeatureCollection","geofenceSchema":true,"dataset":{"id":"d","revision":1,"generatedAt":"2026-11-12T00:00:00Z"},"features":[]}"#, path: "$.geofenceSchema")
        try expectInvalidJSON(#"{"type":"FeatureCollection","geofenceSchema":"1","dataset":{"id":"d","revision":1,"generatedAt":"2026-11-12T00:00:00Z"},"features":[]}"#, path: "$.geofenceSchema")
        try expectInvalidJSON(#"{"type":"NotFC","geofenceSchema":1,"dataset":{"id":"d","revision":1,"generatedAt":"2026-11-12T00:00:00Z"},"features":[]}"#, path: "$.type")
        try expectInvalidJSON(#"[]"#, path: "$")
    }

    @Test func rejectsInvalidDatasetFields() throws {
        try expectInvalid("invalid-revision-zero", path: "$.dataset.revision")
        try expectInvalid("invalid-generated-at", path: "$.dataset.generatedAt")
        try expectInvalidJSON(#"{"type":"FeatureCollection","geofenceSchema":1,"dataset":{"id":"","revision":1,"generatedAt":"2026-11-12T00:00:00Z"},"features":[]}"#, path: "$.dataset.id")
        try expectInvalidJSON(#"{"type":"FeatureCollection","geofenceSchema":1,"dataset":{"id":"d","revision":-1,"generatedAt":"2026-11-12T00:00:00Z"},"features":[]}"#, path: "$.dataset.revision")
        try expectInvalidJSON(#"{"type":"FeatureCollection","geofenceSchema":1,"dataset":{"id":"d","revision":1.5,"generatedAt":"2026-11-12T00:00:00Z"},"features":[]}"#, path: "$.dataset.revision")
        try expectInvalidJSON(#"{"type":"FeatureCollection","geofenceSchema":1,"dataset":{"id":"d","revision":true,"generatedAt":"2026-11-12T00:00:00Z"},"features":[]}"#, path: "$.dataset.revision")
        // Very large integer literals may be decoded as Double by JSONSerialization and lose exactness; reject if not exact.
        try expectInvalidJSON(#"{"type":"FeatureCollection","geofenceSchema":1,"dataset":{"id":"d","revision":9223372036854775808,"generatedAt":"2026-11-12T00:00:00Z"},"features":[]}"#, path: "$.dataset.revision")
        try expectInvalidJSON(#"{"type":"FeatureCollection","geofenceSchema":1,"dataset":{"id":"d","revision":1,"generatedAt":"2026-02-30T00:00:00Z"},"features":[]}"#, path: "$.dataset.generatedAt")
    }

    @Test func rejectsInvalidFeatureAndProperties() throws {
        try expectInvalid("invalid-duplicate-id", path: "$.features[1].id", regionID: "a")
        try expectInvalidJSON(featureJSONNoProperties(), path: "$.features[0].properties", regionID: "f")
        try expectInvalidJSON(featureJSON(properties: #"{"enabled":1}"#), path: "$.features[0].properties.enabled", regionID: "f")
        try expectInvalidJSON(featureJSON(properties: #"{"priority":1.2}"#), path: "$.features[0].properties.priority", regionID: "f")
        try expectInvalidJSON(featureJSON(properties: #"{"priority":true}"#), path: "$.features[0].properties.priority", regionID: "f")
        try expectInvalidJSON(featureJSON(properties: #"{"name":1}"#), path: "$.features[0].properties.name", regionID: "f")
        try expectInvalidJSON(featureJSON(properties: "[]"), path: "$.features[0].properties", regionID: "f")
        try expectInvalidJSON(#"{"type":"FeatureCollection","geofenceSchema":1,"dataset":{"id":"d","revision":1,"generatedAt":"2026-11-12T00:00:00Z"},"features":[{"type":"Feature","id":"","properties":{},"geometry":{"type":"Polygon","coordinates":[[[0,0],[1,0],[1,1],[0,0]]]}}]}"#, path: "$.features[0].id")
    }

    @Test func rejectsTopologyErrorsWithPaths() throws {
        try expectInvalid("invalid-bowtie", path: "$.features[0].geometry.coordinates[0]", regionID: "bow")
        try expectInvalid("invalid-hole-outside", regionID: "h")
        try expectInvalid("invalid-overlapping-holes", regionID: "h")
        try expectInvalid("invalid-antimeridian", regionID: "a")
        try expectInvalidJSON(featureJSON(coords: "[[[0,0],[1,0],[1,1],[0,0.0000000000001]]]"), path: "$.features[0].geometry.coordinates[0]", regionID: "f")
        try expectInvalidJSON(featureJSON(coords: "[[[0,0],[1,0,0],[1,1],[0,0]]]"), path: "$.features[0].geometry.coordinates[0][1]", regionID: "f")
        try expectInvalidJSON(featureJSON(coords: "[[[0,0,0],[1,0],[1,1],[0,0]]]"), path: "$.features[0].geometry.coordinates[0][0]", regionID: "f")
        try expectInvalidJSON(featureJSON(coords: "[[[true,0],[1,0],[1,1],[true,0]]]"), path: "$.features[0].geometry.coordinates[0][0]", regionID: "f")
        // MultiPolygon path (no duplicate .coordinates)
        let multiBad = #"{"type":"FeatureCollection","geofenceSchema":1,"dataset":{"id":"d","revision":1,"generatedAt":"2026-11-12T00:00:00Z"},"features":[{"type":"Feature","id":"m","properties":{},"geometry":{"type":"MultiPolygon","coordinates":[[[[0,0],[2,2],[2,0],[0,2],[0,0]]]]}}]}"#
        try expectInvalidJSON(multiBad, path: "$.features[0].geometry.coordinates[0][0]", regionID: "m")
    }

    private func expectInvalidJSON(_ json: String, path: String? = nil, regionID: String? = nil, reasonContains: String? = nil, sourceLocation: SourceLocation = #_sourceLocation) throws {
        do {
            _ = try decodeJSON(json)
            Issue.record("expected invalid", sourceLocation: sourceLocation)
        } catch let GeofenceError.invalidSnapshot(r, p, reason) {
            if let regionID { #expect(r == regionID, sourceLocation: sourceLocation) }
            if let path { #expect(p == path, sourceLocation: sourceLocation) }
            if let reasonContains { #expect(reason.contains(reasonContains), sourceLocation: sourceLocation) }
        } catch {
            Issue.record("unexpected error \(error)", sourceLocation: sourceLocation)
        }
    }
    private func featureJSON(id: String = "f", properties: String = "{}", coords: String = "[[[0,0],[1,0],[1,1],[0,0]]]") -> String {
        #"{"type":"FeatureCollection","geofenceSchema":1,"dataset":{"id":"d","revision":1,"generatedAt":"2026-11-12T00:00:00Z"},"features":[{"type":"Feature","id":"\#(id)","properties":\#(properties),"geometry":{"type":"Polygon","coordinates":\#(coords)}}]}"#
    }
    private func featureJSONNoProperties(id: String = "f", coords: String = "[[[0,0],[1,0],[1,1],[0,0]]]") -> String {
        #"{"type":"FeatureCollection","geofenceSchema":1,"dataset":{"id":"d","revision":1,"generatedAt":"2026-11-12T00:00:00Z"},"features":[{"type":"Feature","id":"\#(id)","geometry":{"type":"Polygon","coordinates":\#(coords)}}]}"#
    }
}
