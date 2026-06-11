# Tileserver OSM Airgap Manual

## 1. Prerequisites

- Docker with Docker Compose v2.
- Git.
- curl for resumable Geofabrik country downloads.
- Python 3 for the synthetic demo raster MBTiles script.
- PowerShell 7 or Windows PowerShell. Bash wrappers are included for Linux hosts that also have `pwsh`.
- Network access to the internal Artifactory Docker registry and Docker authentication configured on each host.

TileServer GL, Planetiler, and Nginx images must already be mirrored in Artifactory. This project does not pull images from public registries or create, copy, and load Docker image archives.

## 2. Configure Artifactory Images

Create the local environment file:

```powershell
Copy-Item .env.example .env
```

Edit `.env` and replace the example host and repository paths with the full Artifactory references available in the air-gapped network:

```text
TILESERVER_IMAGE=artifactory.example.com/docker/maptiler/tileserver-gl:latest
VIEWER_IMAGE=artifactory.example.com/docker/library/nginx:alpine
PLANETILER_IMAGE=artifactory.example.com/docker/onthegomap/planetiler:latest
OSMIUM_IMAGE=artifactory.example.com/docker/iboates/osmium:latest
```

The exact Artifactory repository layout may differ. The four image variables are mandatory so Docker Compose cannot fall back to Docker Hub or GHCR. The Osmium image must provide an `osmium` executable compatible with `osmium merge`.

## 3. Prepare Non-Image Assets

On a preparation machine with access to the required web and style sources, run from the repo root:

```powershell
.\scripts\vendor-assets.ps1
.\scripts\generate-demo-raster-mbtiles.ps1
docker compose config
```

`vendor-assets.ps1` downloads local copies of:

- MapLibre GL JS and CSS.
- OSM Bright.
- Dark Matter.
- OSM Liberty.
- The subset of OpenMapTiles fonts referenced by the bundled styles.
- Style sprites.

The script rewrites style `sources`, `glyphs`, font stacks, and `sprite` URLs to local TileServer paths. It copies only the required glyph PBF directories and excludes upstream ZIP archives. These web and style assets are copied with the repository; they are separate from container images supplied by Artifactory.

## 4. Generate Vector MBTiles from an Existing PBF

Place the input file under `data/input/`, for example:

```text
data/input/source.osm.pbf
```

Generate OpenMapTiles-compatible vector MBTiles:

```powershell
.\scripts\generate-vector-mbtiles.ps1 `
  -Pbf data/input/source.osm.pbf `
  -Output data/mbtiles/osm-vector.mbtiles
```

By default, the script passes `--download` to Planetiler so it can fetch required OpenMapTiles profile support data during asset preparation. For an air-gapped host that already has the support data cached under `data/`, run:

```powershell
.\scripts\generate-vector-mbtiles.ps1 `
  -Pbf data/input/source.osm.pbf `
  -Output data/mbtiles/osm-vector.mbtiles `
  -Offline
```

For large regions or the planet, increase memory in `.env`:

```text
PLANETILER_JAVA_OPTS=-Xmx32g
```

Planetiler needs fast disk and temporary space. Budget several times the PBF size for working data.

### Generate one MBTiles from multiple countries

The multi-country orchestrator downloads a common dated Geofabrik snapshot, verifies MD5 checksums, merges the extracts with Osmium, and runs Planetiler once:

```powershell
.\scripts\generate-country-mbtiles.ps1 `
  -Countries israel,lebanon,finland `
  -SnapshotDate 2026-06-01 `
  -Output data/mbtiles/osm-vector.mbtiles `
  -Force
```

`israel` is an alias for Geofabrik's `israel-and-palestine` region. The command therefore includes the complete maintained Israel-and-Palestine extract. See [combined-country-mbtiles.md](combined-country-mbtiles.md) for local-PBF, offline, cache, rerun, and troubleshooting procedures.

## 5. Add Existing Raster MBTiles

Copy existing raster MBTiles into:

```text
data/mbtiles/
```

Add each file to `tileserver/config.json` under `data`, then add a matching entry to `viewer/layers.json` under `rasterOverlays`.

Example:

```json
{
  "id": "imagery-2024",
  "label": "Imagery 2024",
  "tiles": "/data/imagery-2024/{z}/{x}/{y}.png",
  "minzoom": 8,
  "maxzoom": 18,
  "opacity": 0.75,
  "visible": false
}
```

TileServer GL reads MBTiles metadata for format and bounds. If a raster source uses 512 px tiles, set `"tileSize": 512` in `tileserver/config.json`.

## 6. Run the Stack

```powershell
docker compose pull tileserver viewer
docker compose up -d tileserver viewer
```

Both commands use the Artifactory image references from `.env`. No Docker image tar is required.

Open:

- TileServer GL: `http://localhost:8080`
- Combined viewer: `http://localhost:8081`

Use the viewer to switch among OSM Bright, Dark Matter, OSM OpenMapTiles, and OSM Liberty, then toggle raster overlays.

## 7. Air-Gapped Deployment Bundle

On the asset preparation machine:

```powershell
.\scripts\prepare-online-bundle.ps1
```

This vendors the non-image web/style assets, optionally creates demo raster MBTiles, and writes `dist/airgap/manifest.json` with the configured image references. It does not pull, save, or package container images.

Copy the prepared repository and required `.osm.pbf` or `.mbtiles` data files to the air-gapped host. Create its `.env` with the correct Artifactory references.

On the air-gapped host, start only the serving stack:

```powershell
.\scripts\load-airgap-bundle.ps1
```

When the air-gapped host must also merge PBFs or generate MBTiles, pull both generation tools from Artifactory:

```powershell
.\scripts\load-airgap-bundle.ps1 -IncludeGenerationTools
```

The script validates the Compose configuration, pulls the requested images from Artifactory, and starts TileServer GL plus the viewer. It assumes Docker is already authenticated to Artifactory.

If the air-gapped host must generate vector MBTiles, copy the `.osm.pbf` into `data/input/` and ensure Planetiler support data was prepared beforehand. Otherwise, generate `data/mbtiles/osm-vector.mbtiles` on the preparation machine and copy the MBTiles file.

## 8. Validation

Run:

```powershell
docker compose config
.\scripts\check-no-remote-style-refs.ps1
```

After starting the stack, verify:

- TileServer front page loads.
- `/data/osm-vector.json` is available after vector MBTiles generation.
- `/data/raster-demo-low.json` and `/data/raster-demo-high.json` are available after demo raster generation.
- `/styles/osm-bright/style.json`, `/styles/dark-matter/style.json`, `/styles/osm-openmaptiles/style.json`, and `/styles/osm-liberty/style.json` load.
- Viewer base switching and overlay opacity controls work.

## 9. GitHub Publication

The repository should not include real `.osm.pbf` or `.mbtiles` files. Confirm before publishing:

```powershell
git status --short
git check-ignore data/input/source.osm.pbf data/mbtiles/osm-vector.mbtiles
```

Create and push a public repo:

```powershell
gh repo create tileserver-osm-airgap --public --source . --remote origin --push
```

If the repository already exists:

```powershell
git remote add origin https://github.com/<owner>/tileserver-osm-airgap.git
git push -u origin main
```

## 10. Notes on the “Official” OSM Style

The OpenStreetMap website standard style is `openstreetmap-carto`, a Mapnik/PostGIS raster rendering stack. This project is intentionally TileServer GL plus OpenMapTiles-compatible vector MBTiles, so it provides `osm-openmaptiles` as the Carto-inspired official-like vector style. Running the exact `openstreetmap-carto` renderer would require a separate raster rendering pipeline and database.
