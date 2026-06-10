# Tileserver OSM Airgap Manual

## 1. Prerequisites

- Docker with Docker Compose v2.
- Git.
- Python 3 for the synthetic demo raster MBTiles script.
- PowerShell 7 or Windows PowerShell. Bash wrappers are included for Linux hosts that also have `pwsh`.

The runtime tile server is `maptiler/tileserver-gl`. Vector MBTiles generation uses `ghcr.io/onthegomap/planetiler`.

## 2. First Online Preparation

From the repo root:

```powershell
Copy-Item .env.example .env
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

The script rewrites style `sources`, `glyphs`, font stacks, and `sprite` URLs to local TileServer paths. It copies only the required glyph PBF directories and excludes upstream ZIP archives.

## 3. Generate Vector MBTiles from an Existing PBF

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

By default, the script passes `--download` to Planetiler so it can fetch required OpenMapTiles profile support data during online preparation. For an offline host that already has the support data cached under `data/`, run:

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

## 4. Add Existing Raster MBTiles

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

## 5. Run the Stack

```powershell
docker compose up -d tileserver viewer
```

Open:

- TileServer GL: `http://localhost:8080`
- Combined viewer: `http://localhost:8081`

Use the viewer to switch among OSM Bright, Dark Matter, OSM OpenMapTiles, and OSM Liberty, then toggle raster overlays.

## 6. Air-Gapped Bundle

On an internet-connected machine:

```powershell
.\scripts\prepare-online-bundle.ps1
```

Copy the repo directory and `dist/airgap/docker-images.tar` to the offline host.

On the offline host:

```powershell
.\scripts\load-airgap-bundle.ps1
```

If the offline host must generate vector MBTiles, copy the `.osm.pbf` into `data/input/` and ensure Planetiler support data was prepared online first. Otherwise, generate `data/mbtiles/osm-vector.mbtiles` online and copy the MBTiles file.

## 7. Validation

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

## 8. GitHub Publication

The repository should not include real `.osm.pbf`, `.mbtiles`, or Docker image tar files. Confirm before publishing:

```powershell
git status --short
git check-ignore data/input/source.osm.pbf data/mbtiles/osm-vector.mbtiles dist/airgap/docker-images.tar
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

## 9. Notes on the “Official” OSM Style

The OpenStreetMap website standard style is `openstreetmap-carto`, a Mapnik/PostGIS raster rendering stack. This project is intentionally TileServer GL plus OpenMapTiles-compatible vector MBTiles, so it provides `osm-openmaptiles` as the Carto-inspired official-like vector style. Running the exact `openstreetmap-carto` renderer would require a separate raster rendering pipeline and database.
