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
if (-not $Memory) { $Memory = "-Xmx8g" }

$pbfPath = Resolve-Path -Path (Join-Path $repoRoot $Pbf) -ErrorAction Stop
$outputPath = Join-Path $repoRoot $Output

$dataRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot "data")).TrimEnd("\", "/") + [System.IO.Path]::DirectorySeparatorChar
$pbfFullPath = [System.IO.Path]::GetFullPath($pbfPath.Path)
$outputFullPath = [System.IO.Path]::GetFullPath($outputPath)

if (-not $pbfFullPath.StartsWith($dataRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "PBF must be under data/ so the Planetiler container can read it. Put it under data/input/."
}
if (-not $outputFullPath.StartsWith($dataRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Output must be under data/ so the Planetiler container can write it. Use data/mbtiles/osm-vector.mbtiles."
}

$pbfRelative = $pbfFullPath.Substring($dataRoot.Length).Replace("\", "/")
$outputRelative = $outputFullPath.Substring($dataRoot.Length).Replace("\", "/")
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputFullPath) | Out-Null

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
