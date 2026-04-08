---
name: infrastructure-discovery
description: Discovers and inspects cloud infrastructure using read-only CLI commands. Use when you need to understand existing infrastructure state, spot drift between Terraform and reality, debug resource issues, or verify post-apply changes. Never writes — all mutations go through Terraform.
---

# Infrastructure Discovery

## Overview

Use cloud CLIs to understand what actually exists in your infrastructure. Terraform state can be stale — the cloud CLI shows reality. This skill is read-only: it never creates, modifies, or deletes resources. When changes are needed, hand off to the `infrastructure-as-code` skill.

All commands use `terraform`. OpenTofu (`tofu`) is a drop-in replacement — swap the binary.

## When to Use

- Understanding what resources exist before writing Terraform
- Checking if a resource is configured correctly
- Debugging infrastructure issues (connectivity, DNS, permissions)
- Detecting drift between Terraform state and cloud reality
- Verifying resources after a user runs `terraform apply`
- Investigating an incident or outage

**When NOT to use:**
- Writing or modifying Terraform code (use `infrastructure-as-code`)
- Running tests on Terraform code (use `infrastructure-testing`)
- When the user explicitly says they don't need cloud CLI inspection

## CLI Tool Check

Before using any cloud CLI, check availability and credentials. Cloud CLI usage is opt-in-by-default — use it unless the user declines.

```
Need cloud CLI?
      │
      ▼
  Is the CLI installed?
    ├── yes → Are credentials configured?
    │           ├── yes → Are they read-only?
    │           │           ├── confirmed → Proceed
    │           │           └── unknown → Run verification command
    │           │                          (see references/cloud-cli-setup.md)
    │           └── no → Point to references/cloud-cli-setup.md
    └── no → Ask user:
              "Cloud CLI (aws/gcloud/az) is not installed.
               I can show you how to install it, or skip CLI
               inspection for this task.
               - Install now (see references/cloud-cli-setup.md)
               - Skip this run only
               - Skip for this session"
```

If the user chooses "skip for session", do not ask again in the current conversation. If "skip this run", ask again on the next task that needs CLI.

### Detect Provider

Determine the provider from context:
- `.tf` files with `provider "aws"` → AWS
- `.tf` files with `provider "google"` → GCP
- `.tf` files with `provider "azurerm"` → Azure
- No `.tf` files → Ask the user which provider

## Read-Only Discovery Commands

Use these patterns to inspect resources. All commands are read-only. **Never run commands that create, modify, or delete resources.**

### AWS

| Resource | Command | Useful Flags |
|---|---|---|
| EC2 instances | `aws ec2 describe-instances` | `--filters "Name=tag:Name,Values=*web*"` `--query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name,Type:InstanceType}'` |
| VPCs | `aws ec2 describe-vpcs` | `--query 'Vpcs[].{ID:VpcId,CIDR:CidrBlock,Name:Tags[?Key==\`Name\`].Value\|[0]}'` |
| Security groups | `aws ec2 describe-security-groups` | `--group-ids sg-xxx` `--query 'SecurityGroups[].{Name:GroupName,Rules:IpPermissions}'` |
| S3 buckets | `aws s3 ls` | `aws s3api get-bucket-policy --bucket NAME` |
| IAM roles | `aws iam list-roles` | `--query 'Roles[].{Name:RoleName,Arn:Arn}'` |
| Route53 DNS | `aws route53 list-hosted-zones` | `aws route53 list-resource-record-sets --hosted-zone-id ID` |
| EKS clusters | `aws eks list-clusters` | `aws eks describe-cluster --name NAME` |
| RDS instances | `aws rds describe-db-instances` | `--query 'DBInstances[].{ID:DBInstanceIdentifier,Engine:Engine,Status:DBInstanceStatus}'` |

### GCP

| Resource | Command | Useful Flags |
|---|---|---|
| Compute instances | `gcloud compute instances list` | `--format="table(name,zone,status,networkInterfaces[0].accessConfigs[0].natIP)"` |
| VPC networks | `gcloud compute networks list` | `--format=json` |
| Firewall rules | `gcloud compute firewall-rules list` | `--filter="network:NETWORK_NAME"` |
| GCS buckets | `gcloud storage ls` | `gcloud storage buckets describe gs://BUCKET` |
| IAM policy | `gcloud projects get-iam-policy PROJECT_ID` | `--flatten="bindings[].members" --filter="bindings.role:roles/editor"` |
| DNS zones | `gcloud dns managed-zones list` | `gcloud dns record-sets list --zone=ZONE` |
| GKE clusters | `gcloud container clusters list` | `gcloud container clusters describe NAME --zone=ZONE` |
| Cloud SQL | `gcloud sql instances list` | `--format="table(name,region,state,databaseVersion)"` |

### Azure

| Resource | Command | Useful Flags |
|---|---|---|
| VMs | `az vm list` | `--output table` `--query "[].{Name:name,RG:resourceGroup,State:powerState}"` |
| VNets | `az network vnet list` | `--query "[].{Name:name,CIDR:addressSpace.addressPrefixes[0]}"` |
| NSGs | `az network nsg list` | `az network nsg rule list --nsg-name NAME --resource-group RG` |
| Storage accounts | `az storage account list` | `--query "[].{Name:name,Kind:kind,SKU:sku.name}"` |
| Role assignments | `az role assignment list` | `--assignee USER_OR_SP` |
| DNS zones | `az network dns zone list` | `az network dns record-set list --zone-name ZONE --resource-group RG` |
| AKS clusters | `az aks list` | `az aks show --name NAME --resource-group RG` |
| SQL servers | `az sql server list` | `--query "[].{Name:name,State:state,FQDN:fullyQualifiedDomainName}"` |

## Drift Detection

Drift is when cloud reality doesn't match Terraform state. Detect it by comparing both sources.

### Process

```
1. Run terraform plan (shows what Terraform thinks needs to change)
      │
      ▼
2. Run cloud CLI commands to see actual resource state
      │
      ▼
3. Compare the two:
   ├── Resource in TF state but not in cloud → Deleted outside TF
   ├── Resource in cloud but not in TF state → Created outside TF
   ├── Resource attributes differ → Modified outside TF
   └── Both match → No drift
      │
      ▼
4. Report findings to user
      │
      ▼
5. If changes needed → Hand off to infrastructure-as-code skill
```

### Example: Detecting Security Group Drift

```bash
# Step 1: Check what Terraform expects
terraform plan -no-color 2>&1 | grep -A5 "security_group"

# Step 2: Check what actually exists
aws ec2 describe-security-groups --group-ids sg-0123456789 \
  --query 'SecurityGroups[0].IpPermissions' --output json

# Step 3: Compare ingress rules — are there rules in AWS
# that aren't in the .tf file? That's drift.
```

### Example: Finding Orphaned Resources

Resources that exist in cloud but have no corresponding Terraform:

```bash
# List all EC2 instances, then check which ones are in TF state
aws ec2 describe-instances \
  --query 'Reservations[].Instances[].{ID:InstanceId,Name:Tags[?Key==`Name`].Value|[0]}' \
  --output table

# Compare against Terraform state
terraform state list | grep aws_instance
```

## Debug Patterns

Common infrastructure issues and how to diagnose them with CLI commands.

### Connectivity Issues

```bash
# AWS: Check security group rules for the instance
aws ec2 describe-security-groups --group-ids sg-xxx \
  --query 'SecurityGroups[0].IpPermissions'

# AWS: Check NACLs on the subnet
aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=subnet-xxx"

# AWS: Check route table
aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=subnet-xxx"

# GCP: Check firewall rules for a network
gcloud compute firewall-rules list --filter="network:NETWORK" --format=json

# Azure: Check NSG rules
az network nsg rule list --nsg-name NSG_NAME --resource-group RG --output table
```

### DNS Not Resolving

```bash
# AWS: Check Route53 records
aws route53 list-resource-record-sets --hosted-zone-id ZONE_ID \
  --query "ResourceRecordSets[?Name=='example.com.']"

# GCP: Check Cloud DNS records
gcloud dns record-sets list --zone=ZONE_NAME --filter="name=example.com."

# Azure: Check DNS records
az network dns record-set list --zone-name example.com --resource-group RG

# Verify external resolution
dig example.com +short
nslookup example.com
```

### Instance Not Starting

```bash
# AWS: Check instance status and system logs
aws ec2 describe-instance-status --instance-ids i-xxx
aws ec2 get-console-output --instance-id i-xxx --output text

# GCP: Check instance serial port output
gcloud compute instances get-serial-port-output INSTANCE --zone=ZONE

# Azure: Check boot diagnostics
az vm boot-diagnostics get-boot-log --name VM_NAME --resource-group RG
```

### Permission Issues

```bash
# AWS: Simulate a policy to check if an action is allowed
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT:role/ROLE \
  --action-names s3:GetObject \
  --resource-arns arn:aws:s3:::bucket-name/*

# GCP: Test IAM permissions
gcloud projects get-iam-policy PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:SERVICE_ACCOUNT"

# Azure: Check role assignments
az role assignment list --assignee PRINCIPAL_ID --output table
```

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "I'll just quick-fix it via CLI" | CLI changes create drift. All writes go through Terraform. |
| "I don't need to check current state" | Assumptions about infra cause plan failures. Always verify first. |
| "The Terraform state is the source of truth" | State can be stale. Cloud CLI shows actual reality. |
| "I can skip the CLI check, I know what's there" | Infrastructure changes constantly. Verify, don't assume. |
| "Read-only access is too restrictive" | Read-only prevents accidental damage. Writes go through Terraform with review. |

## Red Flags

- Running any write/delete/update CLI command
- Skipping CLI verification when credentials are unknown
- Reporting drift without cross-referencing both Terraform state and cloud reality
- Assuming resource configuration without checking
- Using cloud CLI to make changes instead of writing Terraform
- Not offering the user skip-once/skip-session when CLI is unavailable

## Verification

After completing discovery:

- [ ] Only read-only CLI commands were used (no create, modify, delete, update)
- [ ] Drift findings cross-reference both Terraform state and cloud CLI output
- [ ] Any needed changes are handed off to `infrastructure-as-code` skill
- [ ] Cloud CLI availability was checked; user was offered skip-once/skip-session if missing
- [ ] Findings are reported with specific resource IDs and current vs expected state

## See Also

- For cloud CLI installation and credential setup, see `references/cloud-cli-setup.md`
- For writing Terraform code based on discoveries, use the `infrastructure-as-code` skill
- For testing Terraform code, use the `infrastructure-testing` skill
