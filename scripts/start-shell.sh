#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--help" ]]; then
  echo 'Usage: [INSTANCE_ID=i-...] [REGION=...] [AWS_PROFILE=...] [TF_DIR=...] scripts/start-shell.sh'
  exit 0
fi
[[ $# == 0 ]] || { echo 'Use --help; arguments are supplied as environment variables.' >&2; exit 2; }
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
need aws
need session-manager-plugin
resolve_region
INSTANCE_ID="${INSTANCE_ID:-$(tf_output ec2_instance_id)}"
[[ "$INSTANCE_ID" =~ ^i-[0-9a-f]+$ ]] || fail 'Invalid EC2 instance ID.'
printf 'Starting Session Manager shell on %s (%s).\n' "$INSTANCE_ID" "$REGION"
exec aws --region "$REGION" ssm start-session --target "$INSTANCE_ID"
