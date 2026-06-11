#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$repo_root/scripts/generate-country-mbtiles.ps1" "$@"
