# DOKS + AWS IAM Roles Anywhere (PoC)

Private lab proving a DOKS workload can obtain temporary AWS credentials via IAM Roles Anywhere (IAMRA), without long-lived access keys in the app.

Status: working end-to-end PoC. Candidate for `digitalocean/scale-with-simplicity` after review — do not merge there until agreed.

## What this proves

1. Small DOKS cluster
2. Self-signed CA registered as an IAMRA trust anchor (skips paid AWS Private CA for the lab)
3. IAM role + IAMRA profile
4. Demo pod with `aws_signing_helper` sidecar
5. `aws sts get-caller-identity` succeeds from inside the pod using the assumed role

## Prerequisites

- `doctl` authenticated
- `kubectl`, `helm`, `openssl`, `aws` CLI
- AWS identity that can manage IAM + IAM Roles Anywhere
- AWS region set to a real AWS region (e.g. `us-east-1`), never a DigitalOcean region like `sfo3`

## Run order (from this repo root)

```bash
./scripts/01-create-doks-cluster.sh
./scripts/02-setup-aws-iamra.sh
./scripts/03-install-cert-manager.sh
./scripts/04-deploy-demo.sh
./scripts/05-verify.sh
```

Tear down when done:

```bash
./scripts/99-teardown.sh
```

AWS resource cleanup (optional):

```bash
DELETE_AWS=yes ./scripts/99-teardown.sh
```

## Notes

- Phase 1 uses a CA-issued client cert stored in a Kubernetes Secret (simple, reliable).
- cert-manager is installed so we can evolve to automated issuance next; the first verify path does not depend on Private CA.
- Network path to AWS APIs is public HTTPS from DOKS (fine for STS / IAMRA). Aurora/private VPC access would need VPN/PNC separately.
- `.state/` (certs, keys, generated env) is gitignored — never commit it.
