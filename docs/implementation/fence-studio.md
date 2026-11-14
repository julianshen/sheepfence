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

## Quick-add place boundaries — 2026-11-14

Double-click a mapped place, or use Add place at center, to add the smallest usable
containing physical polygon from OpenStreetMap. Existing OSM fences are selected on
repeat double-click without a new request. Export retains source IDs, source URL,
attribution and ODbL reference. Manual drawing disables lookup.

The point query excludes indoor rooms and regional/timezone/administrative relation
outlines. Geometry conversion stitches complete relation member ways, retains holes
and MultiPolygon parts, and validates the entire result. It never fabricates a box
or radius for point-only or unsupported results. Application edits, import/new,
Undo/Redo and explicit cancellation invalidate in-flight results.

Validation:

- 25 JavaScript geometry/lookup tests pass: topology, candidate containment and size,
  actual White House fixture, caching/throttling, cancellation, timeout, HTTP errors,
  malformed/oversized responses and concurrent request exclusion.
- Browser checks with a captured real OSM response pass double-click addition,
  duplicate selection, Undo/Redo, manual drawing isolation, stale-response rejection,
  failed-service handling, snapshot export and mobile layout.
- Production Swift importer: both EditorExportSmokeTests pass, including a snapshot
  exported from the quick-add browser check for White House relation 19761182.
- Live Overpass GET checks returned the real White House polygon. The final filtered
  response was 10,589 bytes with two candidate areas. Public endpoints also produced
  timeouts/504s, including a live browser attempt; mocked-response interaction checks
  are distinguished from those service-availability results.

The current provider is the VK Maps public Overpass instance; its configurable HTTPS
URL is in `assets/editor/places-config.json`. Queries are explicit, serialized,
throttled and cached for the session. They are not initiated on pan or hover. There
is no automatic retry or alternate-provider fan-out. The provider receives the click
coordinate, not the user's existing fence dataset. Public services are best-effort.
