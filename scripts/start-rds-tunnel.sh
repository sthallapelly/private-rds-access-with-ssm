#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--help" ]]; then
  echo 'Usage: [INSTANCE_ID=...] [RDS_HOST=...] [RDS_PORT=3306] [LOCAL_PORT=13306] [REGION=...] [AWS_PROFILE=...] [TF_DIR=...] scripts/start-rds-tunnel.sh'
  echo 'Unset target/host/remote port/region values are read from Terraform outputs.'
  exit 0
fi
[[ $# == 0 ]] || { echo 'Use --help; arguments are supplied as environment variables.' >&2; exit 2; }
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
need aws
need session-manager-plugin
need jq
resolve_region
INSTANCE_ID="${INSTANCE_ID:-$(tf_output ec2_instance_id)}"
RDS_HOST="${RDS_HOST:-$(tf_output rds_endpoint)}"
RDS_PORT="${RDS_PORT:-$(tf_output rds_port)}"
LOCAL_PORT="${LOCAL_PORT:-13306}"
[[ "$INSTANCE_ID" =~ ^i-[0-9a-f]+$ ]] || fail 'Invalid EC2 instance ID.'
[[ "$RDS_HOST" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || fail 'RDS_HOST must be a hostname, without protocol or port.'
valid_port "$RDS_PORT"
valid_port "$LOCAL_PORT"
parameters="$(jq -cn --arg host "$RDS_HOST" --arg remote "$RDS_PORT" --arg local "$LOCAL_PORT" \
  '{host:[$host],portNumber:[$remote],localPortNumber:[$local]}')"
printf 'localhost:%s → SSM → EC2 (%s) → %s:%s\n' "$LOCAL_PORT" "$INSTANCE_ID" "$RDS_HOST" "$RDS_PORT"
printf 'Keep this terminal open; connect a MySQL client over TCP in another terminal. Ctrl-C ends the tunnel.\n'
exec aws --region "$REGION" ssm start-session --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters "$parameters"
