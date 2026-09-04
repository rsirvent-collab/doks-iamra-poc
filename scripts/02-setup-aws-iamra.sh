#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/lib.sh"

require_aws

REGION="$(aws_region)"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
ROLE_NAME="${ROLE_NAME:-doks-iamra-poc-role}"
PROFILE_NAME="${PROFILE_NAME:-doks-iamra-poc-profile}"
TRUST_ANCHOR_NAME="${TRUST_ANCHOR_NAME:-doks-iamra-poc-anchor}"
SESSION_POLICY_NAME="${SESSION_POLICY_NAME:-doks-iamra-poc-session}"

mkdir -p "${CERT_DIR}"
cd "${CERT_DIR}"

log "AWS account ${ACCOUNT} region ${REGION}"

# --- Self-signed root CA (lab only) ---
# IAMRA requires CA:TRUE in basicConstraints (plain openssl -x509 is not enough).
if [[ ! -f ca.key || ! -f ca.crt ]]; then
  log "Generating self-signed CA with CA basicConstraints"
  cat > ca.cnf <<'EOF'
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
CN = doks-iamra-poc-ca

[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
EOF
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout ca.key -out ca.crt -days 365 \
    -config ca.cnf
fi

# --- End-entity cert for the workload ---
if [[ ! -f client.key || ! -f client.crt ]]; then
  log "Generating client certificate signed by CA"
  cat > client.cnf <<'EOF'
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
CN = doks-iamra-demo

[v3_client]
basicConstraints = CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = clientAuth
subjectKeyIdentifier = hash
EOF
  openssl req -newkey rsa:2048 -nodes \
    -keyout client.key -out client.csr \
    -config client.cnf
  openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out client.crt -days 30 -sha256 \
    -extfile client.cnf -extensions v3_client
fi

# --- Trust anchor ---
log "Creating / resolving IAMRA trust anchor"
EXISTING_TA="$(aws rolesanywhere list-trust-anchors --region "${REGION}" \
  --query "trustAnchors[?name=='${TRUST_ANCHOR_NAME}'].trustAnchorArn | [0]" \
  --output text 2>/dev/null || true)"
if [[ -n "${EXISTING_TA}" && "${EXISTING_TA}" != "None" ]]; then
  TRUST_ANCHOR_ARN="${EXISTING_TA}"
  log "Reusing trust anchor ${TRUST_ANCHOR_ARN}"
else
  CA_PEM="$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' ca.crt)"
  cat > "${STATE_DIR}/create-trust-anchor.json" <<EOF
{
  "name": "${TRUST_ANCHOR_NAME}",
  "enabled": true,
  "source": {
    "sourceType": "CERTIFICATE_BUNDLE",
    "sourceData": {
      "x509CertificateData": "${CA_PEM}"
    }
  }
}
EOF
  TRUST_ANCHOR_ARN="$(aws rolesanywhere create-trust-anchor \
    --cli-input-json "file://${STATE_DIR}/create-trust-anchor.json" \
    --region "${REGION}" \
    --query trustAnchor.trustAnchorArn \
    --output text)"
  log "Created trust anchor ${TRUST_ANCHOR_ARN}"
fi

# --- Session / role permissions (STS identity only for the demo) ---
SESSION_POLICY_DOC='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["sts:GetCallerIdentity"],
      "Resource": "*"
    }
  ]
}'

POLICY_ARN="arn:aws:iam::${ACCOUNT}:policy/${SESSION_POLICY_NAME}"
if ! aws iam get-policy --policy-arn "${POLICY_ARN}" >/dev/null 2>&1; then
  log "Creating IAM policy ${SESSION_POLICY_NAME}"
  aws iam create-policy \
    --policy-name "${SESSION_POLICY_NAME}" \
    --policy-document "${SESSION_POLICY_DOC}" >/dev/null
else
  log "Reusing IAM policy ${POLICY_ARN}"
fi

# --- IAM role trust for Roles Anywhere ---
# SourceArn condition filled after trust anchor exists
TRUST_DOC="$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "rolesanywhere.amazonaws.com" },
      "Action": [
        "sts:AssumeRole",
        "sts:SetSourceIdentity",
        "sts:TagSession"
      ],
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "${TRUST_ANCHOR_ARN}"
        }
      }
    }
  ]
}
EOF
)"

if ! aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  log "Creating IAM role ${ROLE_NAME}"
  aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document "${TRUST_DOC}" >/dev/null
else
  log "Updating trust policy on existing role ${ROLE_NAME}"
  aws iam update-assume-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-document "${TRUST_DOC}" >/dev/null
fi

aws iam attach-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-arn "${POLICY_ARN}" >/dev/null || true

ROLE_ARN="$(aws iam get-role --role-name "${ROLE_NAME}" --query Role.Arn --output text)"

# --- IAMRA profile ---
EXISTING_PROFILE="$(aws rolesanywhere list-profiles --region "${REGION}" \
  --query "profiles[?name=='${PROFILE_NAME}'].profileArn | [0]" \
  --output text 2>/dev/null || true)"
if [[ -n "${EXISTING_PROFILE}" && "${EXISTING_PROFILE}" != "None" ]]; then
  PROFILE_ARN="${EXISTING_PROFILE}"
  log "Reusing profile ${PROFILE_ARN}"
else
  PROFILE_ARN="$(aws rolesanywhere create-profile \
    --name "${PROFILE_NAME}" \
    --role-arns "${ROLE_ARN}" \
    --enabled \
    --region "${REGION}" \
    --query profile.profileArn \
    --output text)"
  log "Created profile ${PROFILE_ARN}"
fi

write_env AWS_REGION "${REGION}"
write_env AWS_ACCOUNT "${ACCOUNT}"
write_env TRUST_ANCHOR_ARN "${TRUST_ANCHOR_ARN}"
write_env PROFILE_ARN "${PROFILE_ARN}"
write_env ROLE_ARN "${ROLE_ARN}"
write_env ROLE_NAME "${ROLE_NAME}"

log "Wrote ${ENV_FILE}"
cat "${ENV_FILE}"

log "Local smoke test with aws_signing_helper (if installed) is optional."
log "Next: ./scripts/03-install-cert-manager.sh"
