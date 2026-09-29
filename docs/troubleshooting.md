# Troubleshooting Guide

Use this guide to isolate failures in the private RDS access path.

For detailed experiment results showing how these symptoms were reproduced, see [`failure-experiments.md`](failure-experiments.md).

## Quick diagnosis

| Symptom | Likely boundary | Check first |
|---|---|---|
| `TargetNotConnected` | Managed node / Systems Manager | SSM Agent, managed-node status, endpoint connectivity |
| `ssm` resolves to a public IP | Private DNS | SSM endpoint `PrivateDnsEnabled` |
| `ssmmessages` resolves to a public IP | Private DNS | ssmmessages endpoint `PrivateDnsEnabled` |
| Session Manager works, RDS TCP fails | EC2 → RDS | RDS DNS, SG rules, port 3306 |
| Tunnel starts, MySQL times out | EC2 → RDS | Test TCP 3306 directly from EC2 |
| TCP 3306 works, MySQL rejects login | Database | Username/password and database authentication |
| Agent stopped and no SSM access | Recovery path | Restore/restart the agent through an approved recovery mechanism |
| Terraform proposes unexpected replacement | Terraform lifecycle | Inspect dependency graph and plan before applying |

## `TargetNotConnected`

Check whether Systems Manager currently sees the instance:

```bash id="5ou0he"
AWS_PROFILE=<profile> aws ssm describe-instance-information \
  --region <region>
```

The healthy state is:

```text id="poh3u7"
PingStatus = Online
```

If the instance is not online, check:

1. SSM Agent status
2. EC2 IAM instance profile
3. `ssm` and `ssmmessages` interface endpoint status
4. Private DNS configuration
5. endpoint security-group TCP 443 access
6. managed-node outbound TCP 443 access

If instance access is available through an approved recovery path, check the agent with:

```bash id="8bjuxy"
systemctl is-active amazon-ssm-agent
```

The lab reproduced `TargetNotConnected` both by blocking the endpoint HTTPS path and by stopping the SSM Agent. See [`failure-experiments.md`](failure-experiments.md) for those tests.

## Systems Manager hostname resolves publicly

From the managed node:

```bash id="o52k6v"
getent ahostsv4 ssm.<region>.amazonaws.com
```

and:

```bash id="jj0dqd"
getent ahostsv4 ssmmessages.<region>.amazonaws.com
```

When the corresponding PrivateLink endpoint is being used with Private DNS, each hostname should resolve to its endpoint's private ENI address.

If not, verify:

- the corresponding interface endpoint is `available`
- `PrivateDnsEnabled = true`
- VPC DNS support is enabled
- VPC DNS hostnames are enabled

Check `ssm` and `ssmmessages` independently. A DNS issue affecting one does not prove that the other is affected.

## Session Manager works but RDS is unreachable

If a new Session Manager session succeeds, shift troubleshooting toward the downstream database path.

First verify RDS DNS from EC2:

```bash id="6hrf0a"
getent ahostsv4 <rds-endpoint>
```

The endpoint should resolve privately.

Then test TCP 3306:

```bash id="1d3n2b"
timeout 5 bash -c \
  '</dev/tcp/<rds-endpoint>/3306' \
  && echo "TCP 3306 SUCCESS" \
  || echo "TCP 3306 FAILED"
```

If this fails, check:

- EC2 SG outbound TCP 3306 to the RDS SG
- RDS SG inbound TCP 3306 from the EC2 SG
- RDS availability
- configured database port
- VPC network path

Do not begin by troubleshooting the local Session Manager plugin when EC2 itself cannot reach RDS.

## Tunnel starts but MySQL fails

A message such as:

```text id="mx8w6n"
Port 13306 opened...
Waiting for connections...
```

confirms that the local forwarding session started. It does not prove that EC2 can reach RDS.

Test the downstream TCP connection from EC2 first.

If TCP 3306 succeeds but MySQL returns an authentication error, investigate the database credentials and authentication configuration rather than changing VPC networking.

## Local forwarding port is unavailable

Confirm that the tunnel process is still running:

```bash id="tv5tnd"
./scripts/start-rds-tunnel.sh
```

From another terminal:

```bash id="8qg2xz"
nc -4 -vz 127.0.0.1 13306
```

If the local port is unavailable, check the Session Manager tunnel process and verify that another local process is not already using port `13306`.

## Recovering from an unavailable SSM Agent

This lab intentionally has no SSH or public administrative path.

If the SSM Agent becomes unavailable, Session Manager itself cannot be used to repair that agent.

During the controlled experiment, rebooting the EC2 instance restored the agent because the service was configured to start automatically at boot.

Production environments using Systems Manager as the primary administrative mechanism should define an approved recovery or break-glass procedure appropriate to their security requirements.

## Unexpected Terraform replacement

If a plan proposes replacing an unexpected resource, stop before applying it.

Run:

```bash id="v4stl2"
terraform -chdir=terraform plan
```

Look for replacement indicators and inspect the affected dependency chain.

Do not use targeted Terraform destruction as a normal failure-injection mechanism. The lab demonstrated that Terraform dependency relationships can cause lifecycle effects beyond the individual control being tested.

See [`failure-experiments.md`](failure-experiments.md#terraform-lifecycle-lesson) for the observed case.

## Diagnostic sequence

When the cause is unclear, check in this order:

1. EC2 is running.
2. SSM Agent is active.
3. Managed node reports `Online`.
4. `ssm` and `ssmmessages` resolve as expected.
5. Interface endpoints are available.
6. TCP 443 security-group path is correct.
7. A new Session Manager session succeeds.
8. RDS resolves privately from EC2.
9. EC2 can reach RDS on TCP 3306.
10. Local port forwarding starts.
11. MySQL authentication succeeds.

Stop at the first failed boundary and investigate there.

This prevents a downstream database problem from being mistaken for a Systems Manager problem—or a managed-node connectivity problem from being investigated at the RDS layer.