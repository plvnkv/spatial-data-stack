#!/usr/bin/env bash
set -euo pipefail
if [[ $# != 2 ]]; then
  echo "Usage: tests/smoke.sh SITE.json all|geonode|martin|titiler|recovery" >&2
  exit 2
fi
settings=$(python3 - "$1" <<'PY'
import json, sys

with open(sys.argv[1]) as f:
    site = json.load(f)
for key in ("geonode_host", "martin_host", "titiler_host"):
    print(site[key])
PY
)
mapfile -t hosts <<< "$settings"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

geonode() {
  curl --fail --silent --show-error --max-time 30 "https://${hosts[0]}/" -o "$work/portal.html"
  test -s "$work/portal.html"
}

martin() {
  curl --fail --silent --show-error --max-time 30 "https://${hosts[1]}/catalog" |
    python3 -c 'import json,sys; assert "sample-vector" in json.load(sys.stdin)["tiles"]'
  curl --fail --silent --show-error --max-time 30 \
    "https://${hosts[1]}/sample-vector/0/0/0" -o "$work/sample.mvt"
  test -s "$work/sample.mvt"
}

titiler() {
  local base="https://${hosts[2]}/cog"
  curl --fail --silent --show-error --max-time 30 \
    "$base/tiles/WebMercatorQuad/0/0/0.png?asset=sample-raster" -o "$work/sample.png"
  test -s "$work/sample.png"
  [[ $(curl -sS --max-time 30 -o /dev/null -w '%{http_code}' "$base/info?asset=missing") == 404 ]]
  [[ $(curl -sS --max-time 30 -o /dev/null -w '%{http_code}' \
    "$base/info?asset=sample-raster&url=https://example.org/file.tif") == 400 ]]
}

case "$2" in
  all|recovery) geonode; martin; titiler ;;
  geonode|martin|titiler) "$2" ;;
  *) echo "Unknown smoke test: $2" >&2; exit 2 ;;
esac
echo "Smoke checks passed: $2"
