#!/usr/bin/env bash
# Shared helpers for local PoC scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${ROOT}/.state"
CERT_DIR="${STATE_DIR}/certs"
ENV_FILE="${STATE_DIR}/iamra.env"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

aws_region() {
  aws configure get region 2>/dev/null || echo "${AWS_REGION:-us-east-1}"
}

require_aws() {
  need aws
  need openssl
  local region
  region="$(aws_region)"
  case "${region}" in
    sfo3|nyc1|nyc3|ams3|sgp1|lon1|fra1|tor1|blr1|syd1)
      die "AWS region is '${region}' (a DigitalOcean region). Run: aws configure set region us-east-1"
      ;;
  esac
  aws sts get-caller-identity >/dev/null || die "aws sts get-caller-identity failed"
}

write_env() {
  local key="$1"
  local value="$2"
  mkdir -p "${STATE_DIR}"
  touch "${ENV_FILE}"
  if grep -q "^${key}=" "${ENV_FILE}" 2>/dev/null; then
    # portable-ish replace
    local tmp
    tmp="$(mktemp)"
    grep -v "^${key}=" "${ENV_FILE}" > "${tmp}" || true
    mv "${tmp}" "${ENV_FILE}"
  fi
  printf '%s=%s\n' "${key}" "${value}" >> "${ENV_FILE}"
}

load_env() {
  [[ -f "${ENV_FILE}" ]] || die "Missing ${ENV_FILE}. Run scripts/02-setup-aws-iamra.sh first."
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
}
