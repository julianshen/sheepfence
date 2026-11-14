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
}
