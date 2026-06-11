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

  $images = @(docker compose --profile generate config --images)
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to resolve Docker Compose image references. Copy .env.example to .env and set the Artifactory image paths."
  }

  $manifest = [ordered]@{
    createdAt = (Get-Date).ToString("o")
    images = $images
    imageSource = "Images are pulled from Artifactory inside the air-gapped network; no image archive is included."
    notes = "Copy the prepared repository and required map data to the air-gapped host, configure .env, then run scripts/load-airgap-bundle.ps1. Add -IncludeGenerationTools when the air-gapped host will merge PBFs or generate MBTiles."
  }
  $manifestJson = $manifest | ConvertTo-Json -Depth 4
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText((Join-Path $bundleDir "manifest.json"), $manifestJson, $utf8NoBom)
} finally {
  Pop-Location
}
