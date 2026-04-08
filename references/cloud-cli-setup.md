# Cloud CLI Setup Reference

Quick reference for installing cloud CLIs and configuring read-only credentials for infrastructure discovery. Used by the `infrastructure-discovery`, `infrastructure-as-code`, and `infrastructure-testing` skills.

## Table of Contents

- [AWS CLI](#aws-cli)
- [GCP CLI](#gcp-cli)
- [Azure CLI](#azure-cli)
- [Verifying Read-Only Access](#verifying-read-only-access)

---

## AWS CLI

### Install

| OS | Command |
|---|---|
| macOS | `brew install awscli` |
| Linux | `curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && unzip awscliv2.zip && sudo ./aws/install` |
| Windows | `msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi` |

Verify: `aws --version`

### Create Read-Only Credentials

**Option A: IAM User with ReadOnlyAccess (simplest)**

1. Create an IAM user (console or CLI with admin credentials):
   ```bash
   aws iam create-user --user-name agent-readonly
   aws iam attach-user-policy --user-name agent-readonly \
     --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
   aws iam create-access-key --user-name agent-readonly
   ```
2. Save the `AccessKeyId` and `SecretAccessKey` from the output.

**Option B: Assume a Read-Only Role (recommended for teams)**

1. Create a role with `ReadOnlyAccess` policy and a trust policy allowing your user to assume it.
2. Configure a profile that assumes the role:
   ```ini
   # ~/.aws/config
   [profile agent-readonly]
   role_arn = arn:aws:iam::ACCOUNT_ID:role/AgentReadOnly
   source_profile = default
   region = us-east-1
   ```

### Configure Named Profile

```bash
aws configure --profile agent-readonly
# Enter the AccessKeyId and SecretAccessKey
# Set default region and output format (json recommended)
```

Use the profile: `aws ec2 describe-instances --profile agent-readonly`
Or set as default: `export AWS_PROFILE=agent-readonly`

---

## GCP CLI

### Install

| OS | Command |
|---|---|
| macOS | `brew install google-cloud-sdk` |
| Linux | `curl https://sdk.cloud.google.com \| bash` then `gcloud init` |
| Windows | Download installer from https://cloud.google.com/sdk/docs/install |

Verify: `gcloud --version`

### Create Read-Only Credentials

**Option A: User account with Viewer role (simplest)**

1. Authenticate: `gcloud auth login`
2. Ensure your account has the `roles/viewer` role on the project:
   ```bash
   gcloud projects add-iam-policy-binding PROJECT_ID \
     --member="user:you@example.com" \
     --role="roles/viewer"
   ```

**Option B: Service account with Viewer role (recommended for automation)**

1. Create a service account:
   ```bash
   gcloud iam service-accounts create agent-readonly \
     --display-name="Agent Read-Only"
   ```
2. Grant Viewer role:
   ```bash
   gcloud projects add-iam-policy-binding PROJECT_ID \
     --member="serviceAccount:agent-readonly@PROJECT_ID.iam.gserviceaccount.com" \
     --role="roles/viewer"
   ```
3. Create and download a key:
   ```bash
   gcloud iam service-accounts keys create ~/agent-readonly-key.json \
     --iam-account=agent-readonly@PROJECT_ID.iam.gserviceaccount.com
   ```

### Configure

```bash
# Activate service account
gcloud auth activate-service-account --key-file=~/agent-readonly-key.json

# Set default project
gcloud config set project PROJECT_ID
```

Use with: `gcloud compute instances list --format=json`

---

## Azure CLI

### Install

| OS | Command |
|---|---|
| macOS | `brew install azure-cli` |
| Linux | `curl -sL https://aka.ms/InstallAzureCLIDeb \| sudo bash` |
| Windows | `winget install Microsoft.AzureCLI` |

Verify: `az --version`

### Create Read-Only Credentials

**Option A: User account with Reader role (simplest)**

1. Authenticate: `az login`
2. Assign Reader role on the subscription:
   ```bash
   az role assignment create \
     --assignee you@example.com \
     --role "Reader" \
     --scope /subscriptions/SUBSCRIPTION_ID
   ```

**Option B: Service principal with Reader role (recommended for automation)**

1. Create a service principal with Reader role:
   ```bash
   az ad sp create-for-rbac \
     --name agent-readonly \
     --role "Reader" \
     --scopes /subscriptions/SUBSCRIPTION_ID
   ```
2. Save the `appId`, `password`, and `tenant` from the output.

### Configure

```bash
# Login with service principal
az login --service-principal \
  --username APP_ID \
  --password PASSWORD \
  --tenant TENANT_ID
```

Use with: `az vm list --output table`

---

## Verifying Read-Only Access

After configuring credentials, verify they are truly read-only by attempting a harmless write operation. Each should fail with a permissions error.

### AWS

```bash
aws s3 mb s3://test-readonly-verification-DELETE-ME --profile agent-readonly
# Expected: An error occurred (AccessDenied)
```

### GCP

```bash
gcloud compute networks create test-readonly-verification --project=PROJECT_ID
# Expected: Required 'compute.networks.create' permission
```

### Azure

```bash
az group create --name test-readonly-verification --location eastus
# Expected: AuthorizationFailed
```

If any of these commands **succeed**, your credentials have write access. Revoke and recreate with the read-only instructions above.

### Quick Status Check

| Provider | Command | Expected |
|---|---|---|
| AWS | `aws sts get-caller-identity --profile agent-readonly` | Shows the read-only user/role ARN |
| GCP | `gcloud auth list` | Shows the read-only service account as active |
| Azure | `az account show` | Shows the subscription with Reader access |
