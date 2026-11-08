#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-all}" in
  all|bootstrap|storage|postgis|rustfs|geonode|martin|titiler) target=${1:-all} ;;
  *) echo "Unknown test target: $1" >&2; exit 2 ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [[ $target == bootstrap || $target == all ]]; then
  test -x bootstrap/install.sh
  bash -n bootstrap/install.sh
  helm lint clusters/single-node
  helm template gis-root clusters/single-node > "$work/apps.yaml"
  test "$(rg -c '^kind: Application$' "$work/apps.yaml")" -eq 6
  test "$(rg -c 'repoURL: "https://github.com/plvnkv/spatial-data-stack"' "$work/apps.yaml")" -eq 6
  helm template gis-bootstrap bootstrap/root -f clusters/single-node/values.yaml > "$work/root.yaml"
  rg -q 'path: clusters/single-node' "$work/root.yaml"
fi

for chart in storage postgis rustfs geonode martin titiler; do
  if [[ $target != all && $target != "$chart" ]]; then continue; fi
  values="clusters/single-node/values/$chart.yaml"
  manifest="$work/$chart.yaml"
  helm lint "charts/$chart" -f "$values"
  helm template "$chart" "charts/$chart" --namespace gis -f "$values" > "$manifest"
  case "$chart" in
    storage) rg -q '^reclaimPolicy: Retain$' "$manifest" ;;
    postgis)
      rg -q '^  type: ClusterIP$' "$manifest"
      if rg -q 'NodePort|LoadBalancer' "$manifest"; then exit 1; fi
      ;;
    rustfs)
      if rg -q '^kind: Ingress$|NodePort|LoadBalancer' "$manifest"; then
        echo "RustFS must stay internal" >&2
        exit 1
      fi
      ;;
    geonode|martin|titiler)
      rg -q '^kind: Ingress$' "$manifest"
      rg -q "^  - secretName: $chart-tls$" "$manifest"
      rg -q '^  ipAllowList:' "$manifest"
      ;;
  esac
done

if [[ -n ${KUBECONFORM:-} ]]; then
  "$KUBECONFORM" -strict -summary -kubernetes-version 1.37.0 \
    -skip Application,AppProject,Middleware "$work"
fi
