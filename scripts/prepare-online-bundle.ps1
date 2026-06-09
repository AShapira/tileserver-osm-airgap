param(
  [switch]$SkipFonts,
  [switch]$SkipDemoRaster
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$bundleDir = Join-Path $repoRoot "dist/airgap"
New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null

Push-Location $repoRoot
try {
  & "$PSScriptRoot/vendor-assets.ps1" -SkipFonts:$SkipFonts
  if (-not $SkipDemoRaster) {
    & "$PSScriptRoot/generate-demo-raster-mbtiles.ps1"
  }

  docker compose pull tileserver viewer
  $tileServerImage = if ($env:TILESERVER_IMAGE) { $env:TILESERVER_IMAGE } else { "maptiler/tileserver-gl:latest" }
  $planetilerImage = if ($env:PLANETILER_IMAGE) { $env:PLANETILER_IMAGE } else { "ghcr.io/onthegomap/planetiler:latest" }
  docker pull $planetilerImage

  $images = @(
    $tileServerImage,
    "nginx:alpine",
    $planetilerImage
  )
  docker save -o (Join-Path $bundleDir "docker-images.tar") @images

  $manifest = [ordered]@{
    createdAt = (Get-Date).ToString("o")
    images = $images
    notes = "Copy the repository plus dist/airgap/docker-images.tar to the offline host, then run scripts/load-airgap-bundle.ps1."
  }
  $manifest | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $bundleDir "manifest.json") -Encoding utf8
} finally {
  Pop-Location
}
