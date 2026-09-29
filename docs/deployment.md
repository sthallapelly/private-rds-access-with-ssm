# Deployment Guide

This guide deploys the Private RDS Administrative Access with AWS Systems Manager lab using Terraform.

For architecture context, see the repository [`README.md`](../README.md).

After deployment, continue with [`validation.md`](validation.md).

## Prerequisites

The workstation used to deploy and test the lab requires:

- AWS CLI
- Terraform
- AWS Session Manager plugin
- MySQL client for end-to-end database validation
- access to an AWS account with permissions to create the required resources

Verify the tools before deployment.

```bash id="o2l51v"
aws --version
terraform version
session-manager-plugin
mysql --version
```

The Session Manager plugin may display usage information or an error when invoked without parameters. That is sufficient to confirm that the executable is installed.

## AWS credentials

Configure AWS CLI credentials using your preferred supported authentication mechanism.

If using a named AWS CLI profile:

```bash id="zggrs1"
export AWS_PROFILE=<profile>
```

Verify the active AWS identity before creating resources:

```bash id="w50h1m"
aws sts get-caller-identity
```

Confirm that the returned account and principal are the environment where you intend to deploy the lab.

## Region

The Terraform configuration uses an AWS region defined by the repository configuration/variables.

Verify the intended region before deployment.

For AWS CLI commands outside Terraform, specify the same region explicitly or configure it in the selected AWS CLI profile.

Example:

```bash id="11rw15"
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1
```

Use the region appropriate to your environment.

## Database credentials

Copy the example variable file:

```bash id="omplbh"
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Update the local file with the required values.

Do not commit:

```text id="zvnwr3"
terraform.tfvars
```

The database password is supplied to Terraform as a sensitive variable. It can still exist in Terraform state even when Terraform suppresses it from normal CLI output.

Terraform state must therefore also be treated as sensitive.

## Initialize Terraform

From the repository root:

```bash id="x0wkj1"
terraform -chdir=terraform init
```

This downloads the required providers and initializes the Terraform working directory.

The provider dependency lock file:

```text id="lweozm"
terraform/.terraform.lock.hcl
```

should remain committed to the repository.

The `.terraform/` working directory should not be committed.

## Validate the configuration

Run:

```bash id="hxd6qn"
terraform -chdir=terraform fmt -check
```

Then:

```bash id="m0xum3"
terraform -chdir=terraform validate
```

Resolve any formatting or configuration errors before creating a plan.

## Review the Terraform plan

Create and review a plan:

```bash id="cpqhlr"
terraform -chdir=terraform plan
```

Review the proposed resources before applying.

The tested version of this lab created **21 Terraform-managed resources**.

The exact number can change if the implementation evolves, so resource count should not be used as the primary correctness check.

## Deploy

Apply the configuration:

```bash id="x2dpv1"
terraform -chdir=terraform apply
```

Review the plan and approve the apply when prompted.

Terraform provisions the lab infrastructure, including:

- VPC networking
- private subnets and routing
- security groups
- EC2 IAM role and instance profile
- Systems Manager interface endpoints
- private managed EC2 instance
- private Amazon RDS database
- supporting resources defined by the Terraform configuration

Wait for Terraform to complete successfully before continuing.

## Capture Terraform outputs

After deployment:

```bash id="d3xfhj"
terraform -chdir=terraform output
```

The outputs provide the identifiers and endpoints required by the validation and helper scripts.

Do not publish outputs containing account-specific identifiers or other environment-specific information unless they have been reviewed and sanitized.

## Validate the deployment

Run:

```bash id="1mkzqs"
./scripts/validate.sh
```

If using a named profile:

```bash id="cqqyk5"
AWS_PROFILE=<profile> ./scripts/validate.sh
```

The validation script collects the primary infrastructure and Systems Manager state.

Continue with:

[`validation.md`](validation.md)

for the complete healthy-state validation, including DNS resolution, EC2-to-RDS connectivity, remote-host forwarding, and MySQL authentication.

## Start an interactive Session Manager shell

The repository includes:

```bash id="4uxn69"
./scripts/start-shell.sh
```

Use it when an interactive shell on the managed EC2 instance is required for validation.

No SSH key or inbound SSH rule is required.

## Start the RDS tunnel

Run:

```bash id="pq0p37"
./scripts/start-rds-tunnel.sh
```

Keep the process running while using the local database client.

The default lab flow forwards the configured local port to the private RDS endpoint through the managed EC2 instance.

From another terminal, verify the local port:

```bash id="fy56zp"
nc -4 -vz 127.0.0.1 13306
```

Then connect using the MySQL client:

```bash id="btdt5q"
mysql --protocol=TCP \
  -h 127.0.0.1 \
  -P 13306 \
  -u <database-user> \
  -p
```

The detailed validation and expected results are documented in [`validation.md`](validation.md).

## Controlled failure testing

Do not begin failure testing until the complete healthy baseline has been validated.

The experiments are maintained separately in:

[`failure-experiments.md`](failure-experiments.md)

Failure injection should use temporary, reversible AWS-side changes.

Avoid using targeted Terraform destruction to simulate failures:

```text id="4e4dqo"
terraform destroy -target=...
```

Terraform should remain the definition of the healthy desired state.

## Check Terraform state after experiments

After restoring any manually modified AWS controls:

```bash id="vpbvef"
terraform -chdir=terraform plan
```

Review the plan for unexpected drift before continuing.

A clean or understood plan should be established before destroying the environment.

## Destroy the lab

When testing is complete:

```bash id="o8pc9x"
terraform -chdir=terraform destroy
```

Review the destroy plan carefully before approving it.

The completed lab test successfully destroyed all 21 Terraform-managed resources.

## Verify cleanup

After destruction:

```bash id="nvb2sa"
terraform -chdir=terraform plan
```

Because the Terraform configuration still defines the lab, the expected result after a successful destroy is a plan proposing to **create the environment again**.

In the tested environment, Terraform reported:

```text id="xtk5vn"
Plan: 21 to add, 0 to change, 0 to destroy.
```

This confirmed that the deployed resources had been removed while the Terraform configuration remained capable of recreating them.

Do not apply this plan unless you intend to deploy the lab again.

## Local files that must remain private

Before publishing or sharing the repository, verify that these artifacts are not tracked:

```text id="66j4wc"
terraform/.terraform/
terraform/terraform.tfstate
terraform/terraform.tfstate.*
terraform/terraform.tfvars
terraform/*.tfplan
evidence/
```

These files can contain:

- database credentials
- AWS account and resource identifiers
- IP addresses
- temporary endpoint information
- deployment-specific state

The following files **should** remain in source control:

```text id="f2ht87"
terraform/*.tf
terraform/.terraform.lock.hcl
terraform/terraform.tfvars.example
```

Never use a working-directory ZIP containing Terraform state or local variable files as the public repository artifact.