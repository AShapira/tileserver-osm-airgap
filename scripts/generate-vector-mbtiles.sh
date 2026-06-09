#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pbf="${1:-${OSM_PBF:-data/input/source.osm.pbf}}"
output="${2:-${VECTOR_MBTILES:-data/mbtiles/osm-vector.mbtiles}}"
memory="${PLANETILER_JAVA_OPTS:--Xmx4g}"

cd "$repo_root"
PLANETILER_JAVA_OPTS="$memory" docker compose --profile generate run --rm planetiler \
  --osm-path="/data/${pbf#data/}" \
  --output="/data/${output#data/}" \
  --force \
  --download

