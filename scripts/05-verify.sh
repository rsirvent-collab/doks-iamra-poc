#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/lib.sh"

need kubectl
NS="${NS:-iamra-demo}"

# Prefer a Running pod (avoid Terminating leftover from rollout)
POD="$(kubectl -n "${NS}" get pod -l app=iamra-demo \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[[ -n "${POD}" ]] || die "No Running iamra-demo pod found in ${NS}"

log "Pod: ${POD}"
log "Calling sts get-caller-identity via IAMRA sidecar metadata endpoint"

# Force trailing slash on the endpoint (AWS CLI concatenates 'latest/...' onto the base URL)
kubectl -n "${NS}" exec "${POD}" -c app -- \
  env AWS_EC2_METADATA_SERVICE_ENDPOINT=http://127.0.0.1:9911/ \
      AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE=IPv4 \
      aws sts get-caller-identity

log "Success if Arn is the IAMRA role session (not your IAM user)"
