# Fence Studio validation — 2026-11-14

The GitHub Pages site now includes a browser-local polygon authoring tool at
`editor.html`, with the usage guide at `fence-editor.html`.

## Scope

- Leaflet map with OpenStreetMap attribution and ordinary, cached, on-demand tiles.
- Polygon and MultiPolygon authoring, holes, vertex drag/insert/remove and numeric editing.
- Dataset and feature metadata, revision increment, enabled state and priority.
- All-or-nothing GeoJSON import, deterministic snapshot preview/download, 30-step undo/redo.
- Local draft storage with visible failure status; no fence upload endpoint.
- Geometry and metadata checks before edits are committed or snapshots exported.

## Evidence

- `node --test scripts/tests/editor-model.test.mjs`: 12/12 passed, including crossing,
  touching, degenerate rings, hole topology, invalid metadata, import preservation,
  byte limits and 100 fences × 100 edges.
- Browser integration passed drawing, properties, holes, MultiPolygon parts, vertex
  drag/insertion, undo/redo, invalid drawing/import rejection, file download,
  local-draft restoration, JSON preview and 390 px mobile layout.
- Browser failure checks passed with blocked tiles and disabled local storage;
  imported display names are rendered as text, and dirty metadata forms block
  conflicting edits. Invalid Go coordinates produce an actionable error.
- Real OpenStreetMap tile requests returned HTTP 200 with visible attribution.
- A file downloaded through the browser is preserved as `editor-export.geojson` in
  the Swift test fixtures. `EditorExportSmokeTests` passes with the production
  decoder, confirming the exported two-part MultiPolygon and its interior hole.
- Documentation build validates local links and anchors, including the editor page.

SDK source is unchanged. The existing 139-test checkpoint remains historical;
the editor interoperability check adds one focused regression test.

## Limits

Editor limits: 100 features, 1,000 vertices per ring, 10,000 vertices total and 5 MB
files. The Swift importer remains authoritative. Antimeridian crossings must be
split before import. Map tiles require network access and are a best-effort service.
Draft autosave excludes unfinished drawing points and unapplied forms; downloads
are the portable backup. No real device location was requested in browser testing.

Leaflet is vendored from the official 1.9.4 GitHub release, with license, exact file
hashes and provenance beside the assets. Its JavaScript release build differs from
the npm/CDN build; the CSS matches the published CDN SHA-256 value.
