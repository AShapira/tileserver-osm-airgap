#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tar_path="${1:-dist/airgap/docker-images.tar}"

cd "$repo_root"
docker load -i "$tar_path"
docker compose up -d tileserver viewer

