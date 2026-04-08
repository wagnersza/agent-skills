# Terraform Guard Hook

## Summary

A PreToolUse hook that prevents destructive Terraform/OpenTofu commands from executing in Claude Code sessions. Uses an allowlist approach: only known safe, read-only subcommands are permitted. Everything else is blocked by default.

## Scope

Ships as part of the agent-skills plugin (`hooks/hooks.json`). Any project that installs agent-skills gets terraform/tofu write protection automatically.

## Mechanism

- **Hook type:** PreToolUse with `matcher: "Bash"`
- **Blocking:** Exit code 2 + stderr message (Claude Code's deny mechanism)
- **Passthrough:** Exit code 0 for allowed commands and non-terraform Bash calls

## Allowlist (safe subcommands)

Read-only and formatting commands that never modify infrastructure state:

| Category | Subcommands |
|----------|-------------|
| Planning | `plan`, `show`, `graph` |
| Setup | `init`, `get`, `login`, `logout`, `providers`, `version` |
| Validation | `validate`, `fmt`, `console`, `test` |
| State read | `state list`, `state show`, `state pull` |
| Workspace read | `workspace list`, `workspace show`, `workspace select` |
| Output | `output` |

Everything not on this list is blocked, including but not limited to: `apply`, `destroy`, `import`, `taint`, `untaint`, `state rm`, `state mv`, `state push`, `force-unlock`, and any future subcommands.

## Pattern Matching

The hook must detect terraform/tofu invocations regardless of how they appear in the command string:

- **Binary names:** `terraform`, `tofu`
- **Full paths:** `/usr/local/bin/terraform`, `./terraform`
- **Env var prefixes:** `TF_VAR_foo=bar terraform apply`
- **Chained commands:** `terraform plan && terraform apply` (each segment checked independently)
- **Separators handled:** `&&`, `||`, `;`, `|`

The hook splits the command on these separators and checks each segment for terraform/tofu invocations.

## Files

| File | Purpose |
|------|---------|
| `hooks/terraform-guard.sh` | The hook script |
| `hooks/terraform-guard-test.sh` | Test script (standalone, `bash hooks/terraform-guard-test.sh`) |
| `hooks/TERRAFORM-GUARD.md` | Documentation |
| `hooks/hooks.json` | Updated to add PreToolUse entry |

## Hook Input

The hook receives JSON on stdin from Claude Code:

```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "terraform plan -var-file=prod.tfvars"
  }
}
```

The script extracts `.tool_input.command` via `jq`.

## Hook Registration

Added to `hooks/hooks.json` alongside the existing SessionStart hook:

```json
{
  "hooks": {
    "SessionStart": [ ... existing ... ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/terraform-guard.sh"
          }
        ]
      }
    ]
  }
}
```

## Test Cases

The test script must cover:

**Allowed (exit 0):**
- `terraform plan`
- `terraform init`
- `terraform validate`
- `terraform fmt`
- `terraform show`
- `terraform output`
- `terraform state list`
- `terraform state show`
- `terraform workspace list`
- `tofu plan`
- `tofu init`
- Non-terraform commands (`ls`, `npm test`, etc.)

**Blocked (exit 2):**
- `terraform apply`
- `terraform destroy`
- `terraform apply -auto-approve`
- `terraform import aws_instance.foo i-1234`
- `terraform taint aws_instance.foo`
- `terraform untaint aws_instance.foo`
- `terraform state rm aws_instance.foo`
- `terraform state mv aws_instance.foo aws_instance.bar`
- `terraform state push`
- `terraform force-unlock 12345`
- `tofu apply`
- `tofu destroy`
- `TF_VAR_foo=bar terraform apply`
- `cd infra && terraform apply`
- `terraform plan && terraform apply` (second segment blocked)
- `/usr/local/bin/terraform apply`

## Requirements

- `jq` (for parsing stdin JSON)
- Bash 3.2+

## Out of Scope

- Blocking `terraform` in non-Bash tools (not applicable — terraform runs via Bash)
- CLAUDE.md instructions (the hook enforces at the tool layer, no soft guidance needed)
- Protecting the agent-skills repo itself (would require `.claude/settings.local.json` hooks, separate concern)
