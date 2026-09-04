#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/lib.sh"

need kubectl
need python3
load_env

[[ -f "${CERT_DIR}/client.crt" && -f "${CERT_DIR}/client.key" ]] \
  || die "Missing client certs in ${CERT_DIR}. Re-run scripts/02-setup-aws-iamra.sh"

NS="${NS:-iamra-demo}"

log "Creating namespace ${NS}"
kubectl get ns "${NS}" >/dev/null 2>&1 || kubectl create namespace "${NS}"

log "Creating TLS secret with IAMRA client certificate"
kubectl -n "${NS}" create secret tls iamra-client-cert \
  --cert="${CERT_DIR}/client.crt" \
  --key="${CERT_DIR}/client.key" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Rendering and applying demo workload"
mkdir -p "${ROOT}/.state/rendered"
python3 - "${ROOT}/k8s/demo-deployment.yaml" "${ROOT}/.state/rendered/demo-deployment.yaml" \
  "${TRUST_ANCHOR_ARN}" "${PROFILE_ARN}" "${ROLE_ARN}" "${AWS_REGION}" <<'PY'
import pathlib, sys
src, dst, ta, profile, role, region = sys.argv[1:7]
text = pathlib.Path(src).read_text()
repl = {
    "${TRUST_ANCHOR_ARN}": ta,
    "${PROFILE_ARN}": profile,
    "${ROLE_ARN}": role,
    "${AWS_REGION}": region,
}
for k, v in repl.items():
    text = text.replace(k, v)
pathlib.Path(dst).write_text(text)
print(f"Wrote {dst}")
PY
kubectl apply -f "${ROOT}/.state/rendered/demo-deployment.yaml"

kubectl -n "${NS}" rollout status deploy/iamra-demo --timeout=180s
kubectl -n "${NS}" get pods -o wide

log "Next: ./scripts/05-verify.sh"
