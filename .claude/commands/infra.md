---
description: Infrastructure workflow — discover, write, or test Terraform/OpenTofu code
---

Detect the infrastructure task from context and invoke the appropriate skill:

1. **Detect context:**
   - `.tf` files in working directory or user message references Terraform/infrastructure
   - User mentions debugging, state, drift, or "what exists" → discovery
   - User mentions writing, creating, modifying resources → IaC writing
   - User mentions testing, validation, scanning, or policy → testing

2. **Route to skill(s):**
   - Understand/debug/drift → `infrastructure-discovery`
   - Write/modify Terraform → `infrastructure-as-code`
   - Test/validate/scan → `infrastructure-testing`
   - Ambiguous → Ask the user which workflow they need

3. **If multiple apply, chain:** discover → write → test

Each skill handles its own cloud CLI tool checks (install, skip-once, skip-session) and points to `references/cloud-cli-setup.md` for credential setup.
