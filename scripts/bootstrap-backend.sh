#!/usr/bin/env bash
# One-shot: create the S3 bucket used for Terraform remote state.
#
# Locking uses S3 native lockfiles (Terraform >=1.10) — no DynamoDB table
# required. Bucket has versioning + SSE-S3 + public-access blocked.
#
# Usage:
#   scripts/bootstrap-backend.sh <bucket-name> [region]
set -euo pipefail

BUCKET="${1:?usage: bootstrap-backend.sh <bucket-name> [region]}"
REGION="${2:-us-east-1}"

echo ">>> Creating S3 bucket s3://${BUCKET} in ${REGION}"
if [[ "${REGION}" == "us-east-1" ]]; then
  aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" >/dev/null
else
  aws s3api create-bucket \
    --bucket "${BUCKET}" --region "${REGION}" \
    --create-bucket-configuration "LocationConstraint=${REGION}" >/dev/null
fi

aws s3api put-bucket-versioning \
  --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "${BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

aws s3api put-public-access-block \
  --bucket "${BUCKET}" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

cat <<EOF

Done.

Next:
  cd terraform/envs/dev
  cp backend.hcl.example backend.hcl   # fill in bucket=${BUCKET}
  terraform init -backend-config=backend.hcl
EOF
