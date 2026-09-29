# Validation Guide

This guide validates the healthy state of the deployed lab.

The objective is to verify the implementation at progressively higher levels: infrastructure isolation, Systems Manager connectivity, PrivateLink DNS resolution, EC2-to-RDS connectivity, and finally authenticated database access.

For architecture context, see the repository [`README.md`](../README.md).
For intentional failure testing, see [`failure-experiments.md`](failure-experiments.md).

## 1. Run the validation script

The repository includes a helper script that collects the primary AWS-side configuration and status information:

```bash id="b01fxk"
./scripts/validate.sh
```

When using a named AWS CLI profile:

```bash id="4h26c2"
AWS_PROFILE=<profile> ./scripts/validate.sh
```

The script collects evidence; it does not independently determine that the architecture is secure or correctly configured.

Verify the results against the expected state below.

## 2. Verify infrastructure isolation

### Managed EC2 instance

Confirm:

- instance state is `running`
- a private IPv4 address is assigned
- no public IPv4 address is assigned
- the instance is in the expected private subnet
- the instance uses the managed-node security group

The EC2 security group should have no inbound rules.

Expected outbound access is limited to:

| Destination | Protocol/Port | Purpose |
|---|---|---|
| Systems Manager endpoint SG | TCP 443 | Private Systems Manager connectivity |
| RDS SG | TCP 3306 | MySQL connectivity |

### Private subnet

Verify that the associated route table does not provide the managed node with an Internet Gateway or NAT-based default route.

The lab intentionally demonstrates Systems Manager connectivity without Internet/NAT dependency on the managed-node path.

### Amazon RDS

Confirm:

- `PubliclyAccessible = false`
- the database is associated with the private DB subnet group
- storage encryption is enabled
- the RDS security group allows TCP 3306 only from the managed-node security group

### Interface endpoints

Confirm that these endpoints exist and are `available`:

```text id="m6imct"
com.amazonaws.<region>.ssm
com.amazonaws.<region>.ssmmessages
```

Both should have:

```text id="yudbzh"
PrivateDnsEnabled = true
```

The endpoint security group should allow TCP 443 from the managed-node security group.

## 3. Verify Systems Manager registration

Check managed-instance status:

```bash id="b7szuc"
AWS_PROFILE=<profile> aws ssm describe-instance-information \
  --region <region>
```

The managed EC2 instance should report:

```text id="5flj4u"
PingStatus = Online
```

The tested deployment successfully registered with Systems Manager and reported Amazon SSM Agent version `3.3.4624.0`.

## 4. Start a Session Manager shell

```bash id="fhztnp"
AWS_PROFILE=<profile> aws ssm start-session \
  --target <instance-id> \
  --region <region>
```

A successful connection should begin with output similar to:

```text id="m3lmc8"
Starting session with SessionId: ...
```

No SSH connection, public IP, or EC2 key pair is required.

From the managed node, the SSM Agent version can be checked with:

```bash id="nax29p"
sudo amazon-ssm-agent -version
```

## 5. Verify PrivateLink DNS resolution

From the Session Manager shell, resolve the normal regional Systems Manager hostnames.

### SSM

```bash id="6cwn2j"
getent ahostsv4 ssm.<region>.amazonaws.com
```

The returned private address should match an ENI address associated with the `ssm` interface endpoint.

### Session messaging

```bash id="z48q62"
getent ahostsv4 ssmmessages.<region>.amazonaws.com
```

The returned private address should match an ENI address associated with the `ssmmessages` interface endpoint.

This confirms that the normal AWS service hostnames are resolving to the intended PrivateLink destinations inside the VPC.

## 6. Verify the RDS network path

Resolve the database endpoint from the managed node:

```bash id="uc63zs"
getent ahostsv4 <rds-endpoint>
```

The endpoint should resolve to a private address.

Then test TCP 3306:

```bash id="hhmeww"
timeout 5 bash -c \
  '</dev/tcp/<rds-endpoint>/3306' \
  && echo "TCP 3306 SUCCESS" \
  || echo "TCP 3306 FAILED"
```

Expected:

```text id="0bsyw5"
TCP 3306 SUCCESS
```

This validates the managed-node-to-RDS network path before involving local port forwarding or database credentials.

## 7. Start the RDS tunnel

From the administrator workstation:

```bash id="lrz3xe"
./scripts/start-rds-tunnel.sh
```

The script uses the Systems Manager document:

```text id="wzv0x4"
AWS-StartPortForwardingSessionToRemoteHost
```

and maps the configured local port to the private RDS endpoint through the managed EC2 instance.

Expected output includes:

```text id="hplk7e"
Starting session with SessionId: ...
Port 13306 opened...
Waiting for connections...
```

Keep this terminal open.

## 8. Test the local forwarded port

From another workstation terminal:

```bash id="9f4jzw"
nc -4 -vz 127.0.0.1 13306
```

The connection should succeed.

This confirms that the local forwarding endpoint is available. Database authentication is validated separately.

## 9. Authenticate to RDS

Connect through the forwarded port:

```bash id="7c2obv"
mysql --protocol=TCP \
  -h 127.0.0.1 \
  -P 13306 \
  -u <database-user> \
  -p
```

Enter the database password interactively.

The tested deployment successfully authenticated to Amazon RDS for MySQL.

After connecting, run:

```sql id="joc1fr"
SELECT DATABASE(), USER(), @@hostname, @@port, VERSION();
```

The test environment returned MySQL `8.4.9`.

More importantly, `USER()` identified the client using the managed EC2 private address.

For example:

```text id="u0p5d7"
labadmin@<managed-node-private-IP>
```

This confirms that the downstream database connection originates from the managed node rather than directly from the administrator workstation.

## 10. Healthy-state checklist

Before beginning failure experiments, confirm:

- EC2 has no public IP
- EC2 has no inbound security-group rules
- private subnet has no Internet/NAT default route
- RDS is private
- RDS accepts TCP 3306 from the managed-node SG
- `ssm` endpoint is available with Private DNS enabled
- `ssmmessages` endpoint is available with Private DNS enabled
- managed node reports `Online`
- `ssm.<region>.amazonaws.com` resolves to its endpoint ENI
- `ssmmessages.<region>.amazonaws.com` resolves to its endpoint ENI
- RDS resolves privately
- EC2-to-RDS TCP 3306 succeeds
- remote-host forwarding starts successfully
- MySQL authentication succeeds

This establishes the known-good baseline used by [`failure-experiments.md`](failure-experiments.md).

## Tested result

The deployed lab successfully passed the complete validation sequence.

The healthy implementation demonstrated:

**Private EC2 + PrivateLink connectivity + private RDS reachability + Session Manager remote-host forwarding + authenticated MySQL access**

Raw deployment evidence is intentionally not committed because it contains temporary AWS resource identifiers and environment-specific information.

Terraform state, variable files containing credentials, saved plans, and database passwords must also remain outside source control.