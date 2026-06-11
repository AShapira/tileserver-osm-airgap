# Notices

This project packages configuration and helper scripts for self-hosting OpenStreetMap-derived tiles in an air-gapped environment.

Data attribution must be preserved for generated OSM vector tiles:

- (c) OpenStreetMap contributors
- (c) OpenMapTiles when using the OpenMapTiles schema or styles

Country extracts downloaded by `scripts/generate-country-mbtiles.ps1` are provided by Geofabrik GmbH from OpenStreetMap data under the Open Database License (ODbL). Preserve the OpenStreetMap attribution in every map that uses the generated tiles.

Osmium Tool is GPL-3.0 licensed software maintained by the Osmium project. This repository references an externally supplied Osmium container image; it does not vendor Osmium binaries.

Style and asset sources used by `scripts/vendor-assets.ps1`:

- OSM Bright GL Style from `openmaptiles/osm-bright-gl-style`
- Dark Matter GL Style from `openmaptiles/dark-matter-gl-style`
- OSM Liberty from `maputnik/osm-liberty`
- OpenMapTiles fonts from `openmaptiles/fonts`
- MapLibre GL JS from the MapLibre project

The `osm-openmaptiles` local style is a Carto-inspired OpenMapTiles-compatible vector style. It is not the upstream `openstreetmap-carto` Mapnik/PostGIS raster rendering stack.
