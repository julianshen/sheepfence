# Fence Studio

[Open Fence Studio](editor.html) to create fence data on an OpenStreetMap basemap. The tool runs in your browser and exports a SheepFence `FeatureCollection` ready for `installSnapshot(from:)` or `installSnapshot(data:)`.

## Double-click to add a place

Zoom in, then **double-click a building or place** to add its mapped OpenStreetMap boundary automatically. The tool selects the smallest usable physical place containing the clicked point, assigns its name and a stable OSM feature ID, and adds it as a normal editable fence. No manual tracing is needed. **Add place at center** offers the same action for touch and keyboard users.

For example, enter **38.8977, -77.0365** in the Go field to visit the White House, then double-click its footprint or choose Add place at center. The mapped building boundary is added; it is different from the larger President's Park boundary. Click the surrounding grounds to look for that mapped area instead.

Double-clicking a place already in your dataset selects its existing fence. Undo removes a newly added place. Quick add is disabled while manually drawing. A lookup can be cancelled; starting a new dataset or editing data also prevents an old response from adding a fence later.

Quick add uses actual enclosing polygons, not an address match, bounding rectangle or invented radius. Indoor rooms and administrative boundaries are excluded. If the place is represented only by a point, has incomplete geometry, is over 25 km², or exceeds the editor's geometry limits, draw it manually. Map coverage and community service availability vary; a failed lookup leaves your dataset unchanged.

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

## Union multiple fences

Check the boxes beside two or more fences, choose **Keep name, enabled and priority from**, then choose **Union checked fences** and confirm. Checked shapes are highlighted in gold. The operation replaces those features with one new `union-N` feature; other fences are unchanged. Overlapping areas and shared edges merge, holes remain unless another selected area fills them, and disconnected areas become MultiPolygon parts. This is a geometric union, not a bounding rectangle or convex hull.

The result takes its display name, enabled state and priority from the chosen fence. Original IDs and properties are retained under `properties.unionSources`; OSM attribution and license references are preserved. The result is not marked as an original OSM object. The dataset revision is unchanged: **increment it before publishing edited content**.

Union runs locally in a worker with a 15-second limit. **Cancel union** or Escape stops it. Editing the dataset also cancels pending work. Invalid or oversized results leave the originals unchanged. **Undo** restores every original feature; **Redo** reapplies the union. Saved drafts and downloaded GeoJSON include the completed result.

## Privacy and map tiles

Fence editing and exports are processed locally. Quick add sends the clicked latitude and longitude to the configured OpenStreetMap boundary service; existing fence geometry is not uploaded. Valid committed edits are autosaved in this browser's local storage when available. There is no account, fence-upload endpoint, analytics or location-history upload. Download a backup before clearing browser data or using a different browser; private browsing and storage limits can prevent draft saving. Unfinished drawing points are not autosaved. Do not store sensitive boundary data in a shared browser profile.

OpenStreetMap receives standard tile requests for the areas you view, along with browser/network metadata. The map keeps visible attribution, uses normal browser caching and does not prefetch offline maps. **My location** runs only when you choose it and centers the map without adding the location to the exported dataset.

Map tiles require a network connection and are a best-effort community service. If tiles fail, coordinate editing, importing and exporting still work after the editor has loaded. Fence Studio does not provide an offline basemap or an uptime guarantee. For a high-traffic deployment, configure a tile provider whose terms and capacity fit the usage.

Quick add currently uses the [VK Maps public Overpass instance](https://maps.mail.ru/osm/tools/overpass/) listed by [OpenStreetMap](https://wiki.openstreetmap.org/wiki/Overpass_API#Public_Overpass_API_instances). Requests happen only when you explicitly add a place. There is one in-flight request, a two-second minimum interval, a five-minute session cache for repeated coordinates, a timeout and a 5 MB response limit. There are no automatic retries or background scans. Exported place features retain OSM source identifiers, attribution and the ODbL license reference. Review the [OpenStreetMap copyright and licensing guidance](https://www.openstreetmap.org/copyright) when distributing derived data.

[OpenStreetMap tile policy](https://operations.osmfoundation.org/policies/tiles/) · [OpenStreetMap attribution](https://www.openstreetmap.org/copyright) · [Leaflet](https://leafletjs.com/)

## Developer maintenance

The application lives in `docs/site/editor.html` and `docs/site/assets/editor`. Leaflet 1.9.4 is vendored from its official GitHub release with its license and provenance in `docs/site/assets/vendor/leaflet`. No runtime CDN is required for the library.

Run geometry/export and lookup regressions with `node --test scripts/tests/editor-*.test.mjs`. The HTTPS lookup endpoint and limits live in `docs/site/assets/editor/places-config.json`, so deployments can switch to their own Overpass service. Public services are best-effort; use a provider with suitable capacity for larger deployments. Build the site with `scripts/build_docs.py` as described in [Contributing](contributing.md). Test drawing, edits, import, undo and exported files in a browser before publishing changes.
