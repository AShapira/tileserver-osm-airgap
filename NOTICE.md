# Notices

This project packages configuration and helper scripts for self-hosting OpenStreetMap-derived tiles in an air-gapped environment.

Data attribution must be preserved for generated OSM vector tiles:

- © OpenStreetMap contributors
- © OpenMapTiles when using the OpenMapTiles schema or styles

Style and asset sources used by `scripts/vendor-assets.ps1`:

- OSM Bright GL Style from `openmaptiles/osm-bright-gl-style`
- Dark Matter GL Style from `openmaptiles/dark-matter-gl-style`
- OSM Liberty from `maputnik/osm-liberty`
- OpenMapTiles fonts from `openmaptiles/fonts`
- MapLibre GL JS from the MapLibre project

The `osm-openmaptiles` local style is a Carto-inspired OpenMapTiles-compatible vector style. It is not the upstream `openstreetmap-carto` Mapnik/PostGIS raster rendering stack.

