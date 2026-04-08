---
name: infrastructure-testing
description: Tests Terraform code using the infrastructure testing pyramid. Use when writing new Terraform modules, validating configurations, running security scans, or setting up policy-as-code. For new code only — don't backfill tests on existing infrastructure unless explicitly asked.
---

# Infrastructure Testing

## Overview

Test infrastructure code before it touches real resources. The testing pyramid for Terraform starts with zero-cost static checks at the base and builds up to real-resource integration tests at the top. More tests at the bottom, fewer at the top. For new code only — don't retroactively add tests to existing modules unless the user explicitly asks.

All commands use `terraform`. OpenTofu (`tofu`) is a drop-in replacement — swap the binary.

## When to Use

- After writing new Terraform modules (unit tests required)
- After writing new root configurations (static checks required)
- When security scanning is needed before a plan/apply
- When setting up policy-as-code guardrails
- When the user asks to add tests to existing infrastructure

**When NOT to use:**
- Existing Terraform code that wasn't written in this session (unless user asks)
- Writing Terraform code (use `infrastructure-as-code`)
- Inspecting cloud resources (use `infrastructure-discovery`)

## The Testing Pyramid

```
          ╱╲
         ╱  ╲         Layer 5: Policy-as-Code
        ╱    ╲        OPA/Sentinel against plan JSON
       ╱──────╲       (when compliance requires)
      ╱        ╲
     ╱          ╲     Layer 4: Integration Tests
    ╱            ╲    terraform test command=apply, Terratest
   ╱──────────────╲   (recommended for complex modules)
  ╱                ╲
 ╱                  ╲  Layer 3: Unit Tests
╱                    ╲ terraform test command=plan + mocks
╱────────────────────╲ (required for modules)
╱                      ╲
╱  Layer 2: Security    ╲ checkov/trivy
╱  Scanning              ╲ (always for new code)
╱──────────────────────╲
╱                        ╲
╱  Layer 1: Static        ╲ fmt, validate, tflint
╱  Checks                  ╲ (always, non-negotiable)
╱──────────────────────────╲
```

| Layer | Gate | Tools | Cost |
|---|---|---|---|
| 1. Static | Always, non-negotiable | `terraform fmt`, `terraform validate`, `tflint` | Zero — no cloud access needed |
| 2. Security | Always for new code | Checkov, Trivy | Zero — static analysis only |
| 3. Unit | Required for modules | `terraform test` with `command = plan` + mocks | Zero — plan only, no resources created |
| 4. Integration | Recommended for complex modules | `terraform test` with `command = apply` | Real resources created and destroyed |
| 5. Policy | When compliance requires | OPA/conftest, Sentinel | Zero — analyzes plan JSON |

## Layer 1: Static Checks (Always)

Run these on every Terraform change. No exceptions.

```bash
# Format check — fails if any file needs formatting
terraform fmt -check -recursive

# If formatting fails, fix it:
terraform fmt -recursive

# Validate — checks syntax, references, type correctness
terraform init -backend=false  # init without backend for validation only
terraform validate

# tflint (if available) — catches provider-specific issues
tflint --init
tflint
```

| Tool | What It Catches |
|---|---|
| `terraform fmt` | Inconsistent formatting, indentation |
| `terraform validate` | Invalid references, type mismatches, missing required arguments |
| `tflint` | Deprecated syntax, invalid instance types, naming conventions |

### Tool Check for tflint

```
Is tflint installed?
  ├── yes → Run it
  └── no → Ask user:
            "tflint is not installed but recommended for catching
             provider-specific issues. Options:
             - Install: brew install tflint (macOS) / see tflint docs
             - Skip this run only
             - Skip for this session"
```

## Layer 2: Security Scanning (Always for New Code)

Scan new Terraform code for security misconfigurations before planning.

```bash
# Checkov — if installed
checkov -d . --framework terraform

# Trivy — if installed (absorbed tfsec)
trivy config .

# Neither installed? Ask user.
```

### Tool Check for Security Scanner

```
Is checkov or trivy installed?
  ├── checkov available → Use checkov
  ├── trivy available → Use trivy
  ├── both available → Use checkov (more Terraform-specific rules)
  └── neither → Ask user:
                "No security scanner found. Recommended for catching
                 misconfigurations (public S3 buckets, open security groups,
                 unencrypted storage). Options:
                 - Install checkov: pip install checkov
                 - Install trivy: brew install trivy
                 - Skip this run only
                 - Skip for this session"
```

### Common Findings

| Finding | Severity | Fix |
|---|---|---|
| S3 bucket without encryption | HIGH | Add `server_side_encryption_configuration` block |
| Security group with 0.0.0.0/0 ingress | HIGH | Restrict to specific CIDR ranges |
| RDS without encryption at rest | HIGH | Set `storage_encrypted = true` |
| CloudTrail not enabled | MEDIUM | Add `aws_cloudtrail` resource |
| EBS volume not encrypted | MEDIUM | Set `encrypted = true` |

## Layer 3: Unit Tests (Required for Modules)

Use `terraform test` with `command = plan` and mock providers to test module logic without creating real resources.

### File Structure

```
modules/
  vpc/
    main.tf
    variables.tf
    outputs.tf
    tests/
      basic.tftest.hcl        # Basic functionality tests
      validation.tftest.hcl   # Variable validation tests
```

### Basic Unit Test

```hcl
# tests/basic.tftest.hcl

mock_provider "aws" {}

variables {
  name        = "test-vpc"
  cidr_block  = "10.0.0.0/16"
  environment = "dev"
}

run "creates_vpc_with_correct_cidr" {
  command = plan

  assert {
    condition     = aws_vpc.main.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR block should be 10.0.0.0/16"
  }

  assert {
    condition     = aws_vpc.main.tags["Name"] == "test-vpc"
    error_message = "VPC should be tagged with the provided name"
  }

  assert {
    condition     = aws_vpc.main.tags["Environment"] == "dev"
    error_message = "VPC should be tagged with the environment"
  }
}
```

### Testing Variable Validation

```hcl
# tests/validation.tftest.hcl

mock_provider "aws" {}

run "rejects_invalid_environment" {
  command = plan

  variables {
    name        = "test"
    cidr_block  = "10.0.0.0/16"
    environment = "invalid"
  }

  expect_failures = [
    var.environment,
  ]
}

run "rejects_invalid_cidr" {
  command = plan

  variables {
    name        = "test"
    cidr_block  = "not-a-cidr"
    environment = "dev"
  }

  expect_failures = [
    var.cidr_block,
  ]
}
```

### Testing for_each Logic

```hcl
# tests/subnets.tftest.hcl

mock_provider "aws" {}

variables {
  name        = "test"
  cidr_block  = "10.0.0.0/16"
  environment = "dev"
  subnet_cidrs = {
    "a" = "10.0.1.0/24"
    "b" = "10.0.2.0/24"
  }
}

run "creates_correct_number_of_subnets" {
  command = plan

  assert {
    condition     = length(aws_subnet.private) == 2
    error_message = "Should create one subnet per entry in subnet_cidrs"
  }
}
```

### Running Unit Tests

```bash
# Run all tests
terraform test

# Run a specific test file
terraform test -filter=tests/basic.tftest.hcl

# Verbose output
terraform test -verbose
```

Expected output:
```
tests/basic.tftest.hcl... pass
  run "creates_vpc_with_correct_cidr"... pass
tests/validation.tftest.hcl... pass
  run "rejects_invalid_environment"... pass
  run "rejects_invalid_cidr"... pass
```

## Layer 4: Integration Tests (Recommended for Complex Modules)

Integration tests use `command = apply` to create real resources, verify them, and destroy them. Since they create real infrastructure, **hand off execution to the user**.

```hcl
# tests/integration.tftest.hcl

# NO mock_provider — uses real provider credentials

variables {
  name        = "test-integration"
  cidr_block  = "10.99.0.0/16"
  environment = "test"
}

run "creates_real_vpc" {
  command = apply

  assert {
    condition     = aws_vpc.main.state == "available"
    error_message = "VPC should be in available state after creation"
  }

  assert {
    condition     = output.vpc_id != ""
    error_message = "VPC ID output should not be empty"
  }
}
```

### Handoff for Integration Tests

Integration tests create real resources. Always hand off:

```
Integration tests ready to run!

Execute:  cd modules/vpc && terraform test -filter=tests/integration.tftest.hcl
Creates:  VPC, subnets (in test configuration — will be destroyed after)
Cleanup:  Automatic — terraform test destroys resources after assertions
Cost:     Minimal (VPC is free, subnets are free)
```

### When to Use Terratest Instead

Reach for Terratest (Go) when:
- You need to SSH into instances and run commands
- You need HTTP health checks against deployed services
- You need cross-provider orchestration (Terraform + Helm + K8s)
- You need complex assertion logic beyond simple equality checks

For pure Terraform module testing, `terraform test` is simpler and sufficient.

## Layer 5: Policy-as-Code (When Compliance Requires)

Use OPA/conftest to enforce organizational policies against `terraform plan` output.

### Generate Plan JSON

```bash
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json
```

### Write a Policy (OPA/Rego)

```rego
# policy/terraform.rego
package terraform

deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_s3_bucket"
  not resource.change.after.server_side_encryption_configuration
  msg := sprintf("S3 bucket '%s' must have encryption enabled", [resource.address])
}

deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_security_group_rule"
  resource.change.after.cidr_blocks[_] == "0.0.0.0/0"
  resource.change.after.type == "ingress"
  msg := sprintf("Security group rule '%s' must not allow 0.0.0.0/0 ingress", [resource.address])
}
```

### Run the Policy

```bash
# Install conftest: brew install conftest
conftest test tfplan.json --policy policy/

# Expected output (pass):
# 2 tests, 2 passed, 0 warnings, 0 failures

# Expected output (fail):
# FAIL - tfplan.json - terraform - S3 bucket 'aws_s3_bucket.data' must have encryption enabled
```

### When to Use Policy-as-Code

- Organization requires compliance guardrails (SOC2, HIPAA, PCI)
- Team needs to enforce tagging, encryption, or network policies
- You want to catch policy violations before apply, not after

Don't mandate this for individual projects without compliance requirements.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "It's just a small module, no tests needed" | Small modules grow. `terraform test` with `command = plan` takes minutes to write. |
| "terraform validate is enough" | Validate checks syntax, not logic. Your `for_each` could produce wrong resources and validate won't catch it. |
| "I'll add security scanning in CI" | Catching misconfigs after push wastes a cycle. Run locally first. |
| "Mocking is too complex for Terraform" | `terraform test` mocks since v1.7 are simple. Three lines of HCL. |
| "Existing code doesn't have tests so why bother" | New code gets tested. Existing code is a separate decision for the user. |
| "Integration tests are too expensive" | Most test resources are free or cents. The cost of a broken apply is much higher. |

## Red Flags

- New module code without any `*.tftest.hcl` files
- Skipping `terraform fmt` or `terraform validate`
- Security scanning skipped without user's explicit opt-out
- Integration tests run directly instead of handed off to user
- Adding tests to existing code that wasn't part of the current task
- Using only `terraform validate` as the entire "testing" strategy
- Mock provider missing in unit tests (would try to call real provider)

## Verification

After testing infrastructure code:

- [ ] `terraform fmt -check` passes
- [ ] `terraform validate` succeeds
- [ ] Security scanner ran (or user explicitly opted out with skip-once/skip-session)
- [ ] New modules have `tests/*.tftest.hcl` with `command = plan` tests
- [ ] Integration tests (if any) include cleanup and use handoff pattern
- [ ] No tests were added to existing code unless user requested it
- [ ] Test names describe the behavior being verified

## See Also

- For writing Terraform code to test, use the `infrastructure-as-code` skill
- For inspecting cloud resources during debugging, use the `infrastructure-discovery` skill
- For cloud CLI setup, see `references/cloud-cli-setup.md`
- For general testing patterns and philosophy, see `references/testing-patterns.md`
