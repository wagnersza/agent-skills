# terraform-guard hook

PreToolUse safety hook that blocks destructive Terraform and OpenTofu commands. Uses an allowlist — only known safe, read-only subcommands are permitted. Everything else is denied by default.

## How it works

When Claude Code is about to execute a Bash command, this hook:

1. Extracts the command from the tool input JSON
2. Splits on shell separators (`&&`, `||`, `;`, `|`)
3. Checks each segment for `terraform` or `tofu` invocations
4. Extracts the subcommand and checks it against the allowlist
5. Blocks (exit 2) if any segment contains a disallowed subcommand

## Allowed subcommands

| Category | Subcommands |
|----------|-------------|
| Planning | `plan`, `show`, `graph` |
| Setup | `init`, `get`, `login`, `logout`, `providers`, `version` |
| Validation | `validate`, `fmt`, `console`, `test` |
| State read | `state list`, `state show`, `state pull` |
| Workspace read | `workspace list`, `workspace show`, `workspace select` |
| Output | `output` |

Everything else is blocked, including: `apply`, `destroy`, `import`, `taint`, `untaint`, `state rm`, `state mv`, `state push`, `force-unlock`, and any future subcommands.

## Pattern matching

The hook catches terraform/tofu regardless of:

- Full paths (`/usr/local/bin/terraform apply`)
- Env var prefixes (`TF_VAR_foo=bar terraform apply`)
- Chained commands (`cd infra && terraform apply`)
- Both `terraform` and `tofu` binaries

## Limitations

- Does not detect terraform invoked via `bash -c`, `eval`, or command substitution
- Does not handle nested subshells or process substitution
- This hook is a safety net, not a security sandbox

## Setup

Already registered in `hooks/hooks.json` as part of the agent-skills plugin. No additional configuration needed.

To use in a standalone project, add to `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash path/to/terraform-guard.sh"
          }
        ]
      }
    ]
  }
}
```

## Requirements

- `jq` (for parsing JSON stdin)
- Bash 3.2+

## Testing

Run: `bash hooks/terraform-guard-test.sh`
