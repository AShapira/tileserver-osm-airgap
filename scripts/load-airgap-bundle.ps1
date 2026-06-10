$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $repoRoot
try {
  docker compose --profile generate config | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Invalid Docker Compose configuration. Copy .env.example to .env and set the Artifactory image paths."
  }

  docker compose pull tileserver viewer planetiler
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to pull one or more images from Artifactory. Verify the image paths and existing Docker registry authentication."
  }

  docker compose up -d tileserver viewer
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to start the TileServer and viewer services."
  }
} finally {
  Pop-Location
}
