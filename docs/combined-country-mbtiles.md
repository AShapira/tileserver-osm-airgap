# Combined Country MBTiles

This workflow creates one OpenMapTiles-compatible `osm-vector.mbtiles` from several OpenStreetMap PBF extracts. It is designed for a connected preparation host and for later reuse inside an air-gapped network.

## Processing Architecture

The generator performs these stages:

1. Resolve requested country or region names against Geofabrik's `index-v1.json`.
2. Convert the requested date to Geofabrik's dated filename format.
3. Download each `.osm.pbf` and published `.md5` file with resumable transfers.
4. Verify every PBF before processing it.
5. Merge all inputs into one sorted PBF with `osmium merge`.
6. Run Planetiler once against the merged PBF.
7. Write a provenance manifest beside the merged PBF.

Generated files live below `data/` and are ignored by Git.

## Image Configuration

Copy the environment template and replace all example references with images available from internal Artifactory:

```powershell
Copy-Item .env.example .env
```

Required generation images:

```text
PLANETILER_IMAGE=artifactory.example.com/docker/onthegomap/planetiler:latest
OSMIUM_IMAGE=artifactory.example.com/docker/iboates/osmium:latest
PLANETILER_JAVA_OPTS=-Xmx8g
```

The Osmium image must contain an `osmium` executable. Compose supplies `osmium` as the entrypoint, so the image only needs to support normal Osmium command arguments.

The host also needs curl. The PowerShell generator calls the native curl executable to support resumable downloads on both Windows and Linux.

## Israel, Lebanon, and Finland

Run from the repository root on a connected preparation host:

```powershell
.\scripts\generate-country-mbtiles.ps1 `
  -Countries israel,lebanon,finland `
  -SnapshotDate 2026-06-01 `
  -Output data/mbtiles/osm-vector.mbtiles `
  -Memory "-Xmx8g" `
  -Force
```

Geofabrik does not publish an Israel-only country extract. The script maps `israel` to the maintained `israel-and-palestine` region. The output therefore covers Israel and Palestine, Lebanon, and Finland.

The common snapshot requirement is deliberate. Osmium can deduplicate overlapping OSM objects safely when the extracts represent the same point in time. The script never chooses separate latest files that may have different data timestamps.

## Preview the Plan

Use `-PlanOnly` to resolve names, display URLs and paths, and validate arguments without changing PBF, MBTiles, manifest, or merged files:

```powershell
.\scripts\generate-country-mbtiles.ps1 `
  -Countries israel,lebanon,finland `
  -SnapshotDate 2026-06-01 `
  -PlanOnly
```

## Existing Local PBF Files

Inputs must be under `data/` because the generation containers mount that directory at `/data`:

```powershell
.\scripts\generate-country-mbtiles.ps1 `
  -Pbf data/input/israel.osm.pbf,data/input/lebanon.osm.pbf,data/input/finland.osm.pbf `
  -Output data/mbtiles/osm-vector.mbtiles `
  -Force
```

The script cannot prove that arbitrary local PBF files share a snapshot. The operator is responsible for supplying mutually consistent files.

## Stage Controls

`-DownloadOnly` downloads and verifies named Geofabrik inputs, then stops. It is not valid with local `-Pbf` inputs.

```powershell
.\scripts\generate-country-mbtiles.ps1 `
  -Countries israel,lebanon,finland `
  -SnapshotDate 2026-06-01 `
  -DownloadOnly
```

`-MergeOnly` prepares or reuses downloaded inputs, merges them, writes provenance, and skips Planetiler:

```powershell
.\scripts\generate-country-mbtiles.ps1 `
  -Countries israel,lebanon,finland `
  -SnapshotDate 2026-06-01 `
  -MergeOnly `
  -Force
```

`-Refresh` removes cached named-country PBF and checksum files and downloads them again. It cannot be combined with `-Offline`.

`-Force` permits replacement of the deterministic merged PBF and final MBTiles. Existing country downloads are still reused unless `-Refresh` is also supplied.

## Parameter Reference

| Parameter | Purpose |
| --- | --- |
| `-Countries <name[]>` | Geofabrik IDs, exact names, ISO alpha-2 codes, or the `israel` alias. Cannot be combined with `-Pbf`. |
| `-Pbf <path[]>` | Existing `.osm.pbf` files below `data/`. Cannot be combined with `-Countries`. |
| `-SnapshotDate YYYY-MM-DD` | Required with `-Countries`; selects one dated snapshot for every region. |
| `-Output <path>` | MBTiles output below `data/`; defaults to `data/mbtiles/osm-vector.mbtiles`. |
| `-Memory <JVM option>` | Planetiler heap setting; defaults to `PLANETILER_JAVA_OPTS` or `-Xmx8g`. |
| `-Offline` | Disables Geofabrik and Planetiler downloads and requires all caches locally. |
| `-Refresh` | Re-downloads named-country inputs and rebuilds the merged PBF. Cannot be combined with `-Offline`. |
| `-DownloadOnly` | Downloads and verifies named-country inputs, writes provenance, and stops. |
| `-MergeOnly` | Downloads if needed, merges inputs, writes provenance, and skips Planetiler. |
| `-Force` | Allows merged PBF and MBTiles replacement. |
| `-PlanOnly` | Resolves and displays the plan without changing generated data. |

## Cache and Output Layout

The example creates paths similar to:

```text
data/
  input/
    countries/
      israel-and-palestine-260601.osm.pbf
      israel-and-palestine-260601.osm.pbf.md5
      lebanon-260601.osm.pbf
      finland-260601.osm.pbf
    combined/
      finland_israel-and-palestine_lebanon-260601.osm.pbf
      finland_israel-and-palestine_lebanon-260601.manifest.json
  sources/
    geofabrik-index-v1.json
  mbtiles/
    osm-vector.mbtiles
```

The provenance manifest records the requested names, canonical Geofabrik IDs, URLs, snapshot, checksums, local inputs, merged path, final output, memory setting, and completed processing stage.

## Air-Gapped Operation

On the connected preparation host, first cache all country data:

```powershell
.\scripts\generate-country-mbtiles.ps1 `
  -Countries israel,lebanon,finland `
  -SnapshotDate 2026-06-01 `
  -DownloadOnly
```

Copy the repository, including `data/input/countries/`, `data/sources/geofabrik-index-v1.json`, and any Planetiler support data, to the air-gapped host. Configure `.env` with internal Artifactory references and pull generation tools:

```powershell
.\scripts\load-airgap-bundle.ps1 -IncludeGenerationTools
```

Then generate without any public downloads:

```powershell
.\scripts\generate-country-mbtiles.ps1 `
  -Countries israel,lebanon,finland `
  -SnapshotDate 2026-06-01 `
  -Offline `
  -Force
```

`-Offline` requires the cached Geofabrik index, each PBF, each checksum file, and Planetiler's required support datasets. Missing files cause an immediate error rather than a network fallback.

## Capacity Planning

The June 1, 2026 example contains roughly 900 MB of compressed PBF input. Allow several times that amount for the merged PBF, Planetiler temporary indexes, support datasets, and MBTiles output. Fast SSD storage materially improves generation time.

The default is `-Xmx8g`. Increase it for larger combinations, while leaving memory for memory-mapped files, Docker, and the host OS:

```powershell
-Memory "-Xmx16g"
```

## Serving and Validation

Start the serving stack after generation:

```powershell
docker compose up -d tileserver viewer
```

Validate the configured source:

```powershell
Invoke-RestMethod http://localhost:8080/data/osm-vector.json
```

Open `http://localhost:8081` and inspect Jerusalem, Beirut, and Helsinki. The same `osm-vector.mbtiles` filename is used by the existing TileServer configuration and local styles, so no viewer changes are required.

## Troubleshooting

### Country cannot be resolved

Use a Geofabrik region ID or exact display name. ISO alpha-2 codes are also accepted when the index provides them. `israel` is the only project-specific alias.

### Dated file returns HTTP 404

The selected snapshot was not published for that region. Choose a date visible in the region's Geofabrik raw directory. The script does not silently substitute a different date.

### Download stops partway

Run the same command again. Downloads use a `.part` file and curl resume support. Use `-Refresh` only when the cached partial or complete input should be discarded.

### Checksum mismatch

The invalid PBF is removed. Rerun to download it again. Repeated failures usually indicate a proxy cache or incomplete mirror.

### Osmium fails

Confirm `OSMIUM_IMAGE`, Docker registry authentication, available disk, and that the image runs `osmium merge`. Local PBF inputs must be normal sorted OSM extracts, not arbitrary concatenated files.

### Planetiler runs out of memory

Increase `-Memory`, reduce the country set, and ensure Docker Desktop has enough assigned memory. Do not allocate the entire Docker memory limit to the JVM.

### Output already exists

The workflow protects existing merged and MBTiles outputs. Add `-Force` only after confirming replacement is intended.
