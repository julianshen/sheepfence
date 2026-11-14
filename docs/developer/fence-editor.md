# Fence Studio

[Open Fence Studio](editor.html) to create fence data on an OpenStreetMap basemap. The tool runs in your browser and exports a SheepFence `FeatureCollection` ready for `installSnapshot(from:)` or `installSnapshot(data:)`.

## Draw your first fence

1. Pan and zoom the map, enter **latitude, longitude** in the Go field, or choose **My location** to request your browser's location permission.
2. Choose **Draw fence**. Click or tap at least three points around the region, then choose **Finish boundary**. The editor closes the ring for you.
3. Select the fence and set its stable feature ID, display name, enabled flag and priority. Choose **Apply properties**.
4. Set the dataset ID and revision, then choose **Apply dataset**.
5. Choose **Download GeoJSON**, or **Preview JSON** to inspect and copy the exact output.

GeoJSON coordinates are exported as **longitude, latitude**, even though the Go field and vertex form label latitude first. Downloading repeatedly without editing produces the same bytes. An empty dataset is allowed, but exporting it asks for confirmation because installing a newer empty snapshot removes that dataset's existing regions.

## Edit boundaries

Select a fence from the list or click its shape. Drag the large vertex handles to move them. Click a small **+** handle between vertices to insert a new point. Select a vertex to enter precise coordinates or remove it in the inspector below the fence properties. On narrow screens, the inspector is below the map.

Use **Hole** to draw an excluded area inside the selected polygon part. Holes must remain strictly inside its outer boundary and cannot overlap or touch other holes. **Polygon part** adds a disconnected component to the same feature, converting it to a MultiPolygon. The boundary selector chooses which part or hole you edit. Removing an outer boundary also removes that part's holes.

**Undo** and **Redo** cover completed edits, metadata changes, deletions and imports (up to 30 changes in the current session). While drawing, use **Undo point** or **Cancel**. Escape cancels a draft boundary. Unfinished boundaries and unapplied form edits are not included in the export; apply or cancel them first.

## Import and revisions

Import a SheepFence snapshot, a plain polygon GeoJSON FeatureCollection, or a single Feature. Plain GeoJSON uses the current dataset metadata; missing IDs are assigned and safe numeric IDs become strings. Polygon and MultiPolygon rings and holes are preserved. Unsupported geometry or invalid features reject the entire import without changing the current dataset. Imports replace, rather than merge with, the current dataset after confirmation.

Importing a SheepFence snapshot preserves its revision and generation timestamp. **Increment the revision before installing edited content for an already published dataset.** Use **+ Revision** to advance it and refresh the timestamp. Reformatting bytes at the same revision can cause an SDK revision conflict, even if the geometry is unchanged.

## Validation and scope

The editor checks required metadata, coordinate ranges, closed rings, degenerate rings, self-intersections, hole containment and duplicate feature IDs. Invalid moves are rejected and the last valid shape remains. Antimeridian-crossing edges must be split into separate polygons before import. Features may overlap one another.

Editor limits are 100 features, 1,000 vertices per ring, 10,000 vertices total and a 5 MB import/export limit. They are authoring limits, not a statement of every SDK geometry limit. The basemap uses Web Mercator, so Go navigation is limited to ±85° latitude. This editor's authoring checks are not a substitute for the Swift importer's authoritative validation or real-world boundary verification.

## Privacy and map tiles

Fence data is processed locally. Valid committed edits are autosaved in this browser's local storage when available. There is no account, upload endpoint, analytics, geocoding service or location-history upload. Download a backup before clearing browser data or using a different browser; private browsing and storage limits can prevent draft saving. Unfinished drawing points are not autosaved. Do not store sensitive boundary data in a shared browser profile.

OpenStreetMap receives standard tile requests for the areas you view, along with browser/network metadata. The map keeps visible attribution, uses normal browser caching and does not prefetch offline maps. **My location** runs only when you choose it and centers the map without adding the location to the exported dataset.

Map tiles require a network connection and are a best-effort community service. If tiles fail, coordinate editing, importing and exporting still work after the editor has loaded. Fence Studio does not provide an offline basemap or an uptime guarantee. For a high-traffic deployment, configure a tile provider whose terms and capacity fit the usage.

[OpenStreetMap tile policy](https://operations.osmfoundation.org/policies/tiles/) · [OpenStreetMap attribution](https://www.openstreetmap.org/copyright) · [Leaflet](https://leafletjs.com/)

## Developer maintenance

The application lives in `docs/site/editor.html` and `docs/site/assets/editor`. Leaflet 1.9.4 is vendored from its official GitHub release with its license and provenance in `docs/site/assets/vendor/leaflet`. No runtime CDN is required for the library.

Run geometry/export regressions with `node --test scripts/tests/editor-model.test.mjs`. Build the site with `scripts/build_docs.py` as described in [Contributing](contributing.md). Test drawing, edits, import, undo and exported files in a browser before publishing changes.
