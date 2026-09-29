# Controlled Failure Experiments

After validating the healthy architecture, the lab introduces controlled failures at four different boundaries.

The goal is to observe the resulting symptoms, identify the affected boundary, and verify recovery.

Complete healthy-state validation is documented in [`validation.md`](validation.md). Run that validation before starting these experiments.

## Experiment summary

| Experiment | Change | Observed result | Boundary |
|---|---|---|---|
| RDS access | Remove TCP 3306 authorization from the managed node | SSM remained healthy; MySQL failed | EC2 → RDS |
| PrivateLink access | Remove endpoint TCP 443 authorization | New SSM sessions returned `TargetNotConnected` | EC2 → SSM endpoints |
| Private DNS | Disable Private DNS on the `ssm` endpoint | `ssm` resolved publicly; `ssmmessages` remained private; fresh shell still worked | DNS / SSM service interaction |
| SSM Agent | Stop `amazon-ssm-agent` | New sessions returned `TargetNotConnected` | Managed-node agent |

## Failure-injection approach

Terraform defines the healthy desired state of the lab.

Temporary failures should therefore be introduced through reversible AWS-side changes rather than by destroying Terraform-managed resources.

Recommended workflow:

1. establish the healthy baseline with Terraform
2. run [`validation.md`](validation.md)
3. temporarily change one AWS control
4. observe the result
5. restore the control
6. confirm recovery
7. run `terraform plan` and verify the desired state

Avoid using:

```bash id="0f01jx"
terraform destroy -target=<resource>
```

for failure injection. A targeted destroy can interact with Terraform dependencies and affect resources beyond the control being tested.

---

# Experiment 1 — Block RDS access

## Objective

Test whether a healthy Session Manager connection guarantees downstream database connectivity.

## Inject the failure

Temporarily remove the RDS security-group ingress rule allowing:

```text id="wq9tkm"
TCP 3306
Source: managed-node security group
```

Do not modify the Systems Manager endpoint configuration.

## Test

Confirm that Session Manager remains available.

Then attempt the database connection through the existing or newly established remote-host tunnel:

```bash id="l38yp8"
mysql --connect-timeout=5 \
  --protocol=TCP \
  -h 127.0.0.1 \
  -P 13306 \
  -u <database-user> \
  -p
```

## Observed result

The Session Manager path remained operational.

MySQL failed with an error similar to:

```text id="9pwosb"
ERROR 2013 (HY000):
Lost connection to MySQL server at
'waiting for initial communication packet'
```

## Finding

The test isolated two independent connectivity boundaries:

**Systems Manager session: healthy**  
**Managed EC2 → RDS: failed**

A working Session Manager session or local forwarding process therefore does not prove that the remote database is reachable.

## Recovery

Restore TCP 3306 ingress from the managed-node security group and retry the MySQL connection.

Authentication should succeed again.

---

# Experiment 2 — Block HTTPS to the Systems Manager endpoints

## Objective

Test the managed node's dependency on HTTPS connectivity to the Systems Manager interface endpoints.

## Inject the failure

Temporarily remove the endpoint security-group rule allowing:

```text id="fhbdh5"
TCP 443
Source: managed-node security group
```

## Test

Attempt a **new** Session Manager session:

```bash id="6sd3yu"
AWS_PROFILE=<profile> aws ssm start-session \
  --target <instance-id> \
  --region <region>
```

## Observed result

The new session failed with:

```text id="2tr5s4"
TargetNotConnected
```

## Finding

Unlike Experiment 1, the failure occurred on the managed-node/Systems Manager side.

RDS connectivity was not the first troubleshooting boundary because the managed node itself was no longer available for a new Session Manager session.

## Recovery

Restore TCP 443 from the managed-node security group to the endpoint security group.

Verify that the managed node returns to:

```text id="vp4xf4"
PingStatus = Online
```

and confirm that a new Session Manager session succeeds.

---

# Experiment 3 — Disable Private DNS on the `ssm` endpoint

## Objective

Observe the effect of changing Private DNS for the `ssm` interface endpoint while leaving the `ssmmessages` endpoint unchanged.

This experiment is intentionally observational. It should not assume in advance that the Session Manager shell will fail.

## Baseline

From the managed node:

```bash id="k7i3kg"
getent ahostsv4 ssm.<region>.amazonaws.com
```

and:

```bash id="znx7vf"
getent ahostsv4 ssmmessages.<region>.amazonaws.com
```

Both should resolve to their corresponding private endpoint ENI addresses before the experiment.

## Inject the change

Disable Private DNS on the `ssm` endpoint:

```bash id="jpyy3x"
AWS_PROFILE=<profile> aws ec2 modify-vpc-endpoint \
  --vpc-endpoint-id <ssm-vpc-endpoint-id> \
  --no-private-dns-enabled \
  --region <region>
```

Leave Private DNS enabled on `ssmmessages`.

## Observe DNS

Run again:

```bash id="o5ldz7"
getent ahostsv4 ssm.<region>.amazonaws.com
```

and:

```bash id="x9ky21"
getent ahostsv4 ssmmessages.<region>.amazonaws.com
```

## Observed result

Before the change, the normal `ssm` regional hostname resolved to the private address of the SSM interface endpoint.

After Private DNS was disabled, the same hostname resolved to a public AWS service address.

At the same time, `ssmmessages.<region>.amazonaws.com` continued resolving to its private interface endpoint because its Private DNS configuration had not been changed.

A fresh Session Manager shell could still be established during the test.

## Finding

The experiment demonstrated two things directly:

- Private DNS determines whether the normal `ssm` regional hostname resolves to the private interface endpoint.
- Disabling Private DNS on the `ssm` endpoint alone did not immediately prevent a fresh Session Manager shell under the tested conditions while `ssmmessages` remained privately reachable.

The second observation should be treated as the result of this specific experiment rather than generalized into a claim that the `ssm` endpoint is unnecessary.

For the broader service-path explanation, refer to the related Systems Manager architecture deep dive.

## Recovery

Re-enable Private DNS:

```bash id="c8h3er"
AWS_PROFILE=<profile> aws ec2 modify-vpc-endpoint \
  --vpc-endpoint-id <ssm-vpc-endpoint-id> \
  --private-dns-enabled \
  --region <region>
```

Verify that:

```bash id="npk7s9"
getent ahostsv4 ssm.<region>.amazonaws.com
```

again resolves to the private SSM endpoint address.

---

# Experiment 4 — Stop the SSM Agent

## Objective

Isolate the managed-node agent as an independent Session Manager dependency.

Networking, IAM, endpoints, DNS, and security groups remain unchanged.

## Inject the failure

From an active Session Manager shell:

```bash id="9zy5aa"
sudo systemctl stop amazon-ssm-agent
```

## Test

From another workstation terminal, attempt a **new** Session Manager connection:

```bash id="5ydqud"
AWS_PROFILE=<profile> aws ssm start-session \
  --target <instance-id> \
  --region <region>
```

## Observed result

The new connection failed with:

```text id="ns41b6"
TargetNotConnected
```

## Finding

Healthy networking and IAM are not sufficient when the SSM Agent itself is unavailable.

The experiment also exposed an operational consideration in an architecture with:

- no SSH
- no public IP
- no inbound administrative access

Once the agent was stopped, Session Manager could not be used to restart it.

## Recovery

The lab instance was rebooted through the EC2 control plane.

The SSM Agent service was configured to start automatically, so after reboot:

```bash id="9bfs9c"
systemctl is-active amazon-ssm-agent
```

returned:

```text id="r23kbc"
active
```

A new Session Manager session then succeeded.

A production implementation using Systems Manager as its primary administrative path should define an appropriate recovery or break-glass procedure.

---

# Terraform lifecycle lesson

During an earlier version of Experiment 2, the endpoint security-group rule was removed using targeted Terraform destruction.

The EC2 resource had an explicit dependency on that rule. The dependency affected Terraform's lifecycle behavior and the EC2 instance was replaced during restoration.

This was not a Systems Manager failure. It was a consequence of using Terraform resource lifecycle operations as a failure-injection mechanism.

The Terraform configuration was subsequently simplified so security-group connectivity rules do not unnecessarily own the EC2 lifecycle.

The experiment procedure was also changed permanently:

> **Use Terraform to define the healthy architecture. Use controlled, reversible AWS-side changes to inject runtime failures.**

After each experiment, use:

```bash id="65hv5i"
terraform -chdir=terraform plan
```

to identify any remaining drift before continuing.

---

# Results

The four experiments produced distinguishable symptoms:

| Condition | New SSM session | Database access | Key observation |
|---|---|---|---|
| Healthy baseline | Works | Works | Complete path operational |
| RDS 3306 blocked | Works | Fails | Downstream RDS boundary |
| Endpoint 443 blocked | `TargetNotConnected` | Unavailable through SSM | Managed-node SSM path |
| `ssm` Private DNS disabled only | Worked in tested scenario | Not primary test | `ssm` changed to public DNS resolution |
| SSM Agent stopped | `TargetNotConnected` | Unavailable through SSM | Managed-node software dependency |

These results form the evidence base for the shorter operational diagnostic guide in [`troubleshooting.md`](troubleshooting.md).

## Final recovery

After completing the experiments:

```bash id="99oq7f"
AWS_PROFILE=<profile> ./scripts/validate.sh
```

should again show the expected healthy architecture.

Then run:

```bash id="gwj4tf"
AWS_PROFILE=<profile> terraform -chdir=terraform plan
```

Review any differences before cleanup.

In the tested environment, all failure conditions were successfully recovered and the architecture returned to its intended state.