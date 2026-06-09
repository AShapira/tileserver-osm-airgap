param(
  [string]$ImageTar = "dist/airgap/docker-images.tar"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$tarPath = Join-Path $repoRoot $ImageTar

if (-not (Test-Path $tarPath)) {
  throw "Image bundle not found: $tarPath"
}

docker load -i $tarPath
docker compose up -d tileserver viewer

