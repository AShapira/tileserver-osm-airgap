param(
  [string]$OutputDir = "data/mbtiles"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $PSScriptRoot "create_demo_raster_mbtiles.py"
$target = Join-Path $repoRoot $OutputDir

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
  $python = Get-Command py -ErrorAction SilentlyContinue
}
if (-not $python) {
  throw "Python 3 is required to generate demo raster MBTiles."
}

& $python.Source $scriptPath $target

