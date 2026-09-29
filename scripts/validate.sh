#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--help" ]]; then
  echo 'Usage: [AWS_PROFILE=...] [TF_DIR=...] scripts/validate.sh'
  echo 'Read-only evidence collector. Uses the Region and resource IDs from Terraform state.'
  exit 0
fi
[[ $# == 0 ]] || { echo 'Use --help; no positional arguments accepted.' >&2; exit 2; }
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
need aws
need jq
need terraform
# These outputs deliberately contain no password. Do not export whole Terraform state.
outputs="$(terraform -chdir="$TF_DIR" output -json)"
value() { jq -er --arg key "$1" '.[$key].value' <<< "$outputs"; }
REGION="$(value aws_region)"
node="$(value ec2_instance_id)"
vpc="$(value vpc_id)"
db="$(value rds_identifier)"
node_sg="$(value ec2_security_group_id)"
db_sg="$(value rds_security_group_id)"
endpoint_sg="$(value endpoint_security_group_id)"
aws_read() { aws --region "$REGION" "$@" --output json; }
printf 'Live evidence from %s, captured at %s\n' "$REGION" "$(date -u +%FT%TZ)"
printf '\nEC2: public IPv4 must be absent; inspect every network interface.\n'
aws_read ec2 describe-instances --instance-ids "$node" --query \
 'Reservations[].Instances[].{ID:InstanceId,State:State.Name,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress,Subnet:SubnetId,VPC:VpcId,AMI:ImageId,Profile:IamInstanceProfile.Arn,SGs:SecurityGroups,Interfaces:NetworkInterfaces[].{ID:NetworkInterfaceId,Private:PrivateIpAddress,Public:Association.PublicIp}}'
printf '\nRDS: PubliclyAccessible must be false.\n'
aws_read rds describe-db-instances --db-instance-identifier "$db" --query \
 'DBInstances[].{ID:DBInstanceIdentifier,Status:DBInstanceStatus,Endpoint:Endpoint,PubliclyAccessible:PubliclyAccessible,SGs:VpcSecurityGroups,Subnets:DBSubnetGroup.Subnets[].SubnetIdentifier,MultiAZ:MultiAZ}'
printf '\nSecurity groups: compare sources, destinations and ports with docs/validation.md.\n'
aws_read ec2 describe-security-groups --group-ids "$node_sg" "$db_sg" "$endpoint_sg"
printf '\nRoute tables: expect only the VPC local route; no internet default route.\n'
aws_read ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc"
printf '\nVPC DNS attributes: both must be true.\n'
aws_read ec2 describe-vpc-attribute --vpc-id "$vpc" --attribute enableDnsSupport
aws_read ec2 describe-vpc-attribute --vpc-id "$vpc" --attribute enableDnsHostnames
printf '\nInterface endpoints, private DNS and actual ENI private addresses:\n'
while IFS= read -r endpoint; do
  details="$(aws_read ec2 describe-vpc-endpoints --vpc-endpoint-ids "$endpoint")"
  jq '.VpcEndpoints[] | {VpcEndpointId,ServiceName,State,PrivateDnsEnabled,SubnetIds,Groups,DnsEntries,NetworkInterfaceIds}' <<< "$details"
  while IFS= read -r eni; do
    aws_read ec2 describe-network-interfaces --network-interface-ids "$eni" --query \
      'NetworkInterfaces[].{ID:NetworkInterfaceId,IP:PrivateIpAddress,Subnet:SubnetId,SGs:Groups,Status:Status}'
  done < <(jq -r '.VpcEndpoints[].NetworkInterfaceIds[]' <<< "$details")
done < <(jq -er '.ssm_vpc_endpoint_ids.value[]' <<< "$outputs")
printf '\nSSM registration: expect Online and AgentVersion >= 3.3.40.0; an empty list is NOT success.\n'
aws_read ssm describe-instance-information --filters "Key=InstanceIds,Values=$node" --query \
 'InstanceInformationList[].{ID:InstanceId,Ping:PingStatus,LastPing:LastPingDateTime,AgentVersion:AgentVersion,Platform:PlatformName}'
printf '\nService names to resolve INSIDE the managed node:\n'
value ssm_service_hostnames
printf '\nCollection complete. This is evidence, not a pass verdict. Follow docs/validation.md for live DNS and database checks.\n'
