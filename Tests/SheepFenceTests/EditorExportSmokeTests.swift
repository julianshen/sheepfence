import Foundation
import Testing
@testable import SheepFence

@Suite struct EditorExportSmokeTests {
    @Test func browserDownloadImportsWithPartsAndHole() async throws {
        // Downloaded from a browser-driven Fence Studio session using synthetic map points.
        let url = try #require(Bundle.module.url(forResource: "editor-export", withExtension: "geojson"))
        let snapshot = try GeoJSONDecoder.decode(Data(contentsOf: url))
        #expect(snapshot.metadata.revision == 2)
        #expect(snapshot.regions.count == 1)
        let region = try #require(snapshot.regions.first)
        #expect(region.geometry.polygons.count == 2)
        #expect(region.geometry.polygons[0].rings.count == 2)
    }

    @Test func quickAddedWhiteHouseImports() throws {
        // Actual OSM footprint exported by Fence Studio's quick-add browser check.
        let url = try #require(Bundle.module.url(forResource: "quick-add-white-house", withExtension: "geojson"))
        let snapshot = try GeoJSONDecoder.decode(Data(contentsOf: url))
        #expect(snapshot.regions.count == 1)
        let region = try #require(snapshot.regions.first)
        #expect(region.id.featureID == "osm-relation-19761182")
        #expect(region.name == "White House")
        #expect(region.geometry.polygons.count == 1)
    }

    @Test func unionExportImportsWithHoleAndDisconnectedPart() throws {
        // Exported by the browser union worker, combining three source fences.
        let url = try #require(Bundle.module.url(forResource: "union-export", withExtension: "geojson"))
        let snapshot = try GeoJSONDecoder.decode(Data(contentsOf: url))
        #expect(snapshot.metadata.revision == 1)
        #expect(snapshot.regions.count == 1)
        let region = try #require(snapshot.regions.first)
        #expect(region.id.featureID == "union-1")
        #expect(region.name == "Chosen 日本語")
        #expect(region.geometry.polygons.count == 2)
        #expect(region.geometry.polygons[0].rings.count == 2)
    }

}
