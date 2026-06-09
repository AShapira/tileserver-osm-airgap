param(
  [string]$Pbf = $env:OSM_PBF,
  [string]$Output = $env:VECTOR_MBTILES,
  [string]$Memory = $env:PLANETILER_JAVA_OPTS,
  [switch]$Offline
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not $Pbf) { $Pbf = "data/input/source.osm.pbf" }
if (-not $Output) { $Output = "data/mbtiles/osm-vector.mbtiles" }
if (-not $Memory) { $Memory = "-Xmx4g" }

$pbfPath = Resolve-Path -Path (Join-Path $repoRoot $Pbf) -ErrorAction Stop
$outputPath = Join-Path $repoRoot $Output
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPath) | Out-Null

$pbfRelative = [System.IO.Path]::GetRelativePath((Join-Path $repoRoot "data"), $pbfPath.Path).Replace("\", "/")
$outputRelative = [System.IO.Path]::GetRelativePath((Join-Path $repoRoot "data"), $outputPath).Replace("\", "/")

if ($pbfRelative.StartsWith("..")) {
  throw "PBF must be under data/ so the Planetiler container can read it. Put it under data/input/."
}
if ($outputRelative.StartsWith("..")) {
  throw "Output must be under data/ so the Planetiler container can write it. Use data/mbtiles/osm-vector.mbtiles."
}

$env:PLANETILER_JAVA_OPTS = $Memory
$args = @(
  "--osm-path=/data/$pbfRelative",
  "--output=/data/$outputRelative",
  "--force"
)
if (-not $Offline) {
  $args += "--download"
}

docker compose --profile generate run --rm planetiler @args

