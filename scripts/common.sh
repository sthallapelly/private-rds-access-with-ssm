#!/usr/bin/env bash
# Shared local helpers; never read database credentials.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${TF_DIR:-$SCRIPT_DIR/../terraform}"
export AWS_PAGER=""
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"; }
tf_output() {
  need terraform
  terraform -chdir="$TF_DIR" output -raw "$1"
}
resolve_region() {
  REGION="${REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-}}}"
  if [[ -z "$REGION" ]]; then REGION="$(tf_output aws_region)"; fi
  [[ -n "$REGION" ]] || fail 'Set REGION or deploy the Terraform configuration first.'
}
valid_port() {
  [[ "$1" =~ ^[0-9]{1,5}$ ]] || fail "Invalid TCP port: $1"
  (( 10#$1 >= 1 && 10#$1 <= 65535 )) || fail "TCP port out of range: $1"
}
