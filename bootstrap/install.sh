#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ $# -lt 4 || $# -gt 5 || $1 != --site || $3 != --secrets-dir || ${5:---without-applications} != --without-applications ]]; then
  echo "Usage: sudo bootstrap/install.sh --site FILE --secrets-dir DIR [--without-applications]" >&2
  exit 2
fi

base=$(cd "$(dirname "$0")/.." && pwd)
site=$2
secrets=$4
settings=$(python3 - "$site" <<'PY'
import ipaddress, json, re, sys
from pathlib import PurePosixPath

site = json.load(open(sys.argv[1]))
site.setdefault("repo_url", "https://github.com/plvnkv/spatial-data-stack")
assert re.fullmatch(r"https://github\.com/[\w.-]+/[\w.-]+", site["repo_url"]), "Invalid GitHub HTTPS URL"
assert re.fullmatch(r"[\w./-]+", site["branch"]), "Invalid Git ref"
for name in ("lan_cidr", "admin_cidr"):
    ipaddress.ip_network(site[name])
data = PurePosixPath(site["data_dir"])
assert len(data.parts) > 1 and data.is_absolute() and ".." not in data.parts, "Invalid data_dir"
for name in ("geonode_host", "martin_host", "titiler_host"):
    assert re.fullmatch(r"[a-z0-9][a-z0-9.-]+", site[name]), "Invalid DNS hostname"
for name in ("repo_url", "branch", "lan_cidr", "data_dir", "geonode_host", "martin_host", "titiler_host"):
    print(site[name])
PY
)
mapfile -t config <<< "$settings"
repo=${config[0]}
branch=${config[1]}
lan=${config[2]}
data=${config[3]}
[[ $EUID == 0 ]] || { echo "Run as root" >&2; exit 2; }
. /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 26.04 ]] || { echo "Ubuntu 26.04 is required" >&2; exit 2; }
[[ -d $secrets ]] || { echo "Missing Secrets directory" >&2; exit 2; }
. "$base/bootstrap/versions.env"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
install -d /etc/rancher/k3s/config.yaml.d /var/lib/rancher/k3s/server/manifests "$data"
cat > /etc/rancher/k3s/config.yaml.d/50-gis.yaml <<YAML
write-kubeconfig-mode: "0600"
default-local-storage-path: "$data"

secrets-encryption: true
YAML
cat > /var/lib/rancher/k3s/server/manifests/gis-traefik.yaml <<'YAML'
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    service:
      spec:
        externalTrafficPolicy: Local
YAML

if ! command -v k3s >/dev/null || ! systemctl is-active --quiet k3s; then
  curl -fsSL --retry 3 https://get.k3s.io -o "$work/k3s-install"
  INSTALL_K3S_VERSION="$K3S_VERSION" sh "$work/k3s-install"
fi
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
k() { k3s kubectl "$@"; }
for attempt in {1..60}; do
  if [[ -n $(k get nodes -o name 2>/dev/null) ]]; then break; fi
  sleep 2
done

k wait node --all --for=condition=Ready --timeout=300s

arch=$(dpkg --print-architecture)
case "$arch" in amd64|arm64) ;; *) echo "Unsupported architecture" >&2; exit 2 ;; esac
archive="helm-$HELM_VERSION-linux-$arch.tar.gz"
curl -fsSL --retry 3 "https://get.helm.sh/$archive" -o "$work/$archive"
curl -fsSL --retry 3 "https://get.helm.sh/$archive.sha256sum" -o "$work/$archive.sha256sum"
(cd "$work" && sha256sum -c "$archive.sha256sum")
tar -xzf "$work/$archive" -C "$work"
helm="$work/linux-$arch/helm"
for namespace in argocd gis; do
  k create namespace "$namespace" --dry-run=client -o yaml | k apply -f -
done

# Create-once. Operators rotate existing credentials explicitly.
for dir in "$secrets"/{gis,argocd}/*/; do
  [[ -d $dir ]] || continue
  name=$(basename "$dir")
  namespace=$(basename "$(dirname "${dir%/}")")
  if [[ -z $(k -n "$namespace" get secret "$name" --ignore-not-found -o name) ]]; then
    k -n "$namespace" create secret generic "$name" --from-file="$dir"
  fi
  if [[ $namespace == argocd && $name == github-repo ]]; then
    k -n argocd label secret "$name" argocd.argoproj.io/secret-type=repository --overwrite
  fi
done

"$helm" upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm \
  --version "$ARGO_CHART_VERSION" --namespace argocd --wait --timeout 10m \
  --set server.service.type=ClusterIP
k -n argocd wait deployment/argocd-server --for=condition=Available --timeout=300s

if [[ ${5:-} == --without-applications ]]; then exit 0; fi

"$helm" template gis-bootstrap "$base/bootstrap/root" --namespace argocd \
  --set-string "repoURL=$repo,branch=$branch,lanCIDR=$lan,dataDir=$data" \
  --set-string "geonodeHost=${config[4]},martinHost=${config[5]},titilerHost=${config[6]}" |
  k apply -f -
