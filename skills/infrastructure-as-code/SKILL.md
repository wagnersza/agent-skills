---
name: infrastructure-as-code
description: Writes and manages Terraform/OpenTofu infrastructure code. Use when creating new infrastructure resources, modifying existing Terraform configurations, managing state, or refactoring modules. Always hands off terraform apply and destroy to the user.
---

# Infrastructure as Code

## Overview

Write Terraform code that is readable, testable, and safe to apply. The agent writes and plans — the user applies. This skill never runs `terraform apply`, `terraform destroy`, or any state-mutating command. Every change ends with a handoff: the exact command, a summary of changes, verification steps, and a rollback plan.

All commands use `terraform`. OpenTofu (`tofu`) is a drop-in replacement — swap the binary.

## When to Use

- Creating new infrastructure resources (VPC, EC2, RDS, GKE, etc.)
- Modifying existing Terraform configurations
- Creating or refactoring Terraform modules
- Setting up remote state backends
- Importing existing resources into Terraform
- Any task involving `.tf` files

**When NOT to use:**
- Inspecting existing infrastructure without changes (use `infrastructure-discovery`)
- Testing Terraform code (use `infrastructure-testing`)
- Pure cloud CLI operations with no Terraform involvement

**New code only:** When working in existing Terraform projects, only modify what was asked. Don't refactor surrounding modules, add tests to existing code, or "improve" naming unless the user requests it.

## The Workflow

```
Task: Create or modify infrastructure
        │
        ▼
  1. Understand current state
     ├── .tf files exist? → Read them, understand structure
     ├── Cloud CLI available? → Use infrastructure-discovery skill
     └── Greenfield? → Scaffold: provider, backend, variables
        │
        ▼
  2. Write Terraform code
     ├── Follow existing project conventions
     ├── Variables with validation + descriptions
     ├── Locals for computed values
     └── Data sources for existing resources
        │
        ▼
  3. Format and validate (non-negotiable)
     ├── terraform fmt
     └── terraform validate
        │
        ▼
  4. Plan
     ├── terraform plan -out=tfplan
     ├── Show FULL plan output to user
     └── Provide human-readable summary
        │
        ▼
  5. Handoff (NEVER run apply or destroy)
     ┌─────────────────────────────────────────┐
     │ Configuration ready for apply!           │
     │                                          │
     │ Execute:  cd <path> && terraform apply   │
     │           tfplan                         │
     │ Changes:  3 to add, 1 to change,        │
     │           0 to destroy                   │
     │ Verify:   <cloud CLI commands>           │
     │ Rollback: <revert steps if needed>       │
     └─────────────────────────────────────────┘
        │
        ▼
  6. After user applies → Verify with cloud CLI (if available)
```

## Writing Patterns

### Provider Pinning

Always pin provider versions to prevent unexpected breaking changes:

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

### Variables with Validation

Every variable gets a description. Add validation blocks for constrained values:

```hcl
variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the web servers"
  type        = string
  default     = "t3.micro"
}
```

### for_each Over count

Prefer `for_each` — it uses map keys, so removing an item doesn't shift indices:

```hcl
# Good: for_each with a map
resource "aws_subnet" "private" {
  for_each = {
    "a" = "10.0.1.0/24"
    "b" = "10.0.2.0/24"
    "c" = "10.0.3.0/24"
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = "${var.region}${each.key}"

  tags = { Name = "private-${each.key}" }
}

# Avoid: count with index
# Removing item [1] shifts all subsequent resources
```

### Data Sources for Existing Resources

Reference resources that exist but aren't managed by this Terraform:

```hcl
data "aws_vpc" "existing" {
  filter {
    name   = "tag:Name"
    values = ["production-vpc"]
  }
}

resource "aws_subnet" "new" {
  vpc_id     = data.aws_vpc.existing.id
  cidr_block = "10.0.100.0/24"
}
```

### Moved Blocks for Refactoring

When renaming or restructuring resources, use `moved` blocks to avoid destroy/recreate:

```hcl
moved {
  from = aws_instance.web
  to   = aws_instance.web_server
}
```

### Locals for Computed Values

Use locals to avoid repeating expressions:

```hcl
locals {
  name_prefix = "${var.project}-${var.environment}"
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
```

## Module Conventions

### When to Create a Module

- **Do create a module** when: the same resource pattern is used 2+ times with different inputs, or the module encapsulates a logical unit (e.g., "VPC with subnets and NAT gateway")
- **Don't create a module** for: a single resource, a one-off configuration, or when it adds indirection without reuse

### Module Structure

```
modules/
  vpc/
    main.tf          # Resources
    variables.tf     # Input variables with descriptions and validation
    outputs.tf       # Output values
    versions.tf      # Required providers and versions
    README.md        # Generated with terraform-docs or written manually
    tests/           # terraform test files (see infrastructure-testing skill)
      basic.tftest.hcl
```

### Module Interface

```hcl
# variables.tf — the module's API
variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR block"
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "Must be a valid CIDR block."
  }
}

# outputs.tf — what consumers need
output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = [for s in aws_subnet.private : s.id]
}
```

## State Management

### Remote Backend First

Always configure a remote backend. Local state gets lost.

```hcl
# AWS S3 backend
terraform {
  backend "s3" {
    bucket         = "myproject-terraform-state"
    key            = "env/prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

# GCP GCS backend
terraform {
  backend "gcs" {
    bucket = "myproject-terraform-state"
    prefix = "env/prod"
  }
}

# Azure Blob backend
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstateaccount"
    container_name       = "tfstate"
    key                  = "env/prod/terraform.tfstate"
  }
}
```

### State Commands Require Confirmation

Never run these without explicit user confirmation:
- `terraform state rm` — removes a resource from state (resource still exists in cloud)
- `terraform state mv` — moves a resource in state (can cause duplicates if wrong)
- `terraform state push` — overwrites remote state
- `terraform import` — adds existing resource to state

Always present these as a handoff:
```
State operation needed!

Execute: terraform state mv aws_instance.old aws_instance.new
Effect:  Renames the resource in state (no cloud changes)
Verify:  terraform plan (should show no changes)
Rollback: terraform state mv aws_instance.new aws_instance.old
```

## The Handoff

Every apply, destroy, or state mutation ends with a handoff. This is non-negotiable.

### Template

```
Configuration ready for apply!

Execute:     cd <path> && terraform apply tfplan
Changes:     <N> to add, <N> to change, <N> to destroy
Key changes: <bullet list of the most important resources affected>
Verify:      <cloud CLI commands to confirm resources exist post-apply>
Rollback:    <specific steps — terraform apply with previous state,
              terraform destroy for new resources, or revert commit>
```

### Handoff Rules

1. **Always show the full plan output** before the handoff summary
2. **Always include verification commands** — cloud CLI commands the user can run after apply to confirm the resources are correct
3. **Always include rollback** — what to do if the apply goes wrong
4. **Never run apply, destroy, or state commands yourself**
5. **If the plan shows destroys** — highlight them prominently and explain why

## Secrets

Never store secrets in `.tf` files or `.tfvars` files committed to git.

| Secret Type | Where to Store |
|---|---|
| Database passwords | AWS SSM Parameter Store, GCP Secret Manager, Azure Key Vault |
| API keys | Same as above, or HashiCorp Vault |
| TLS certificates | ACM (AWS), Certificate Manager (GCP), Key Vault (Azure) |
| Terraform variables | `terraform.tfvars` in `.gitignore`, or CI/CD environment variables |

```hcl
# Good: Reference a secret from SSM
data "aws_ssm_parameter" "db_password" {
  name = "/myapp/prod/db_password"
}

resource "aws_db_instance" "main" {
  password = data.aws_ssm_parameter.db_password.value
}

# Bad: Hardcoded secret
resource "aws_db_instance" "main" {
  password = "supersecret123"  # NEVER do this
}
```

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "I'll just apply this small change" | Small changes destroy production. Always handoff. |
| "State surgery will be faster" | State commands are irreversible without backups. Terraform plan is the safe path. |
| "This module is too simple for variables" | Hardcoded values prevent reuse. Variables with validation from the start. |
| "I'll add the backend later" | Local state gets lost. Remote backend first. |
| "count is fine here" | `count` shifts indices when items are removed. `for_each` is almost always better. |
| "I know what the plan will show" | Run the plan. Assumptions kill infrastructure. |

## Red Flags

- Running `terraform apply` or `terraform destroy`
- Running `terraform state` commands without user confirmation
- Hardcoded values that should be variables
- Missing provider version pinning
- Secrets in `.tf` files or `.tfvars` committed to git
- Modifying existing code beyond what was asked
- Local state backend in any shared or production configuration
- Using `count` when `for_each` would be more stable
- Missing handoff template after writing Terraform code

## Verification

After completing infrastructure code:

- [ ] `terraform fmt` passes with no changes
- [ ] `terraform validate` succeeds
- [ ] `terraform plan` output shown to user with human-readable summary
- [ ] Handoff template provided with execute, changes, verification, rollback
- [ ] No `apply`, `destroy`, or `state` commands were executed
- [ ] No secrets in Terraform files
- [ ] Provider versions are pinned
- [ ] Variables have descriptions and validation where appropriate

## See Also

- For cloud CLI inspection before writing code, use the `infrastructure-discovery` skill
- For testing Terraform code after writing, use the `infrastructure-testing` skill
- For cloud CLI setup, see `references/cloud-cli-setup.md`
