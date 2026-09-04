#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/lib.sh"

CLUSTER_NAME="${CLUSTER_NAME:-doks-iamra-poc}"
REGION="${DO_REGION:-sfo3}"
NODE_SIZE="${NODE_SIZE:-s-2vcpu-4gb}"
NODE_COUNT="${NODE_COUNT:-1}"

log "Creating DOKS cluster ${CLUSTER_NAME} in ${REGION} (${NODE_COUNT}x ${NODE_SIZE})"

if doctl kubernetes cluster get "${CLUSTER_NAME}" >/dev/null 2>&1; then
  log "Cluster ${CLUSTER_NAME} already exists"
else
  doctl kubernetes cluster create "${CLUSTER_NAME}" \
    --region "${REGION}" \
    --version latest \
    --size "${NODE_SIZE}" \
    --count "${NODE_COUNT}" \
    --wait
fi

doctl kubernetes cluster kubeconfig save "${CLUSTER_NAME}"
kubectl config current-context
kubectl get nodes

mkdir -p "${ROOT}/.state"
echo "${CLUSTER_NAME}" > "${ROOT}/.state/cluster_name"

log "DOKS ready"
