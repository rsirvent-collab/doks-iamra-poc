#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/lib.sh"

NS="${NS:-iamra-demo}"
CLUSTER_NAME="${CLUSTER_NAME:-}"
if [[ -z "${CLUSTER_NAME}" && -f "${STATE_DIR}/cluster_name" ]]; then
  CLUSTER_NAME="$(cat "${STATE_DIR}/cluster_name")"
fi
CLUSTER_NAME="${CLUSTER_NAME:-doks-iamra-poc}"

log "Deleting Kubernetes demo resources (best effort)"
kubectl delete ns "${NS}" --ignore-not-found=true || true
helm uninstall cert-manager -n cert-manager 2>/dev/null || true
kubectl delete ns cert-manager --ignore-not-found=true || true

if [[ "${DELETE_CLUSTER:-yes}" == "yes" ]]; then
  log "Deleting DOKS cluster ${CLUSTER_NAME}"
  doctl kubernetes cluster delete "${CLUSTER_NAME}" --force || true
fi

if [[ "${DELETE_AWS:-ask}" == "yes" ]]; then
  load_env
  REGION="${AWS_REGION}"
  log "Deleting AWS IAMRA resources (best effort)"
  # Profiles / trust anchors need IDs from ARNs
  PROFILE_ID="${PROFILE_ARN##*/}"
  TA_ID="${TRUST_ANCHOR_ARN##*/}"
  aws rolesanywhere delete-profile --profile-id "${PROFILE_ID}" --region "${REGION}" || true
  aws rolesanywhere delete-trust-anchor --trust-anchor-id "${TA_ID}" --region "${REGION}" || true
  aws iam detach-role-policy --role-name "${ROLE_NAME}" \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT}:policy/doks-iamra-poc-session" || true
  aws iam delete-role --role-name "${ROLE_NAME}" || true
  aws iam delete-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT}:policy/doks-iamra-poc-session" || true
fi

log "Teardown requested steps done. AWS cleanup: re-run with DELETE_AWS=yes if desired."
log "Local state kept in ${STATE_DIR} (certs/env). Remove manually if you want a clean slate."
