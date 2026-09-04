#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/lib.sh"

need helm
need kubectl

log "Installing cert-manager (for future automated issuance; demo Secret path works without it)"

helm repo add jetstack https://charts.jetstack.io
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --wait

kubectl -n cert-manager get pods

log "cert-manager installed"
log "Next: ./scripts/04-deploy-demo.sh"
