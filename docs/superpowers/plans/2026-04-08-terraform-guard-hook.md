# Terraform Guard Hook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a PreToolUse hook that blocks destructive terraform/tofu commands using an allowlist of safe read-only subcommands.

**Architecture:** A single bash script (`terraform-guard.sh`) receives JSON stdin from Claude Code's PreToolUse hook, extracts the Bash command, splits on shell separators, checks each segment for terraform/tofu invocations, and blocks (exit 2) any subcommand not on the allowlist. Registered via `hooks/hooks.json`.

**Tech Stack:** Bash 3.2+, jq

---

### Task 1: Write the terraform-guard test script

**Files:**
- Create: `hooks/terraform-guard-test.sh`

This test script follows the pattern in `hooks/simplify-ignore-test.sh` — standalone, feeds mock JSON to the hook, asserts exit codes.

- [ ] **Step 1: Create the test script with all test cases**

```bash
#!/bin/bash
# terraform-guard-test.sh — Tests for the terraform-guard hook
#
# Feeds mock JSON stdin to terraform-guard.sh and asserts exit codes.
# Run: bash hooks/terraform-guard-test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/terraform-guard.sh"

PASS=0 FAIL=0

# Helper: run hook with a command string, return exit code
run_hook() {
  local cmd="$1"
  local rc=0
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd" \
    | bash "$HOOK" >/dev/null 2>&1 || rc=$?
  printf '%d' "$rc"
}

assert_allowed() {
  local label="$1" cmd="$2"
  local rc
  rc=$(run_hook "$cmd")
  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf '  PASS: ALLOW — %s\n' "$label"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL: ALLOW — %s (got exit %s)\n' "$label" "$rc" >&2
  fi
}

assert_blocked() {
  local label="$1" cmd="$2"
  local rc
  rc=$(run_hook "$cmd")
  if [ "$rc" -eq 2 ]; then
    PASS=$((PASS + 1))
    printf '  PASS: BLOCK — %s\n' "$label"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL: BLOCK — %s (got exit %s, expected 2)\n' "$label" "$rc" >&2
  fi
}

# ── Allowed commands (exit 0) ───────────────────────────────────────────

printf 'Allowed commands:\n'

assert_allowed "terraform plan" "terraform plan"
assert_allowed "terraform plan with flags" "terraform plan -var-file=prod.tfvars"
assert_allowed "terraform init" "terraform init"
assert_allowed "terraform init -upgrade" "terraform init -upgrade"
assert_allowed "terraform validate" "terraform validate"
assert_allowed "terraform fmt" "terraform fmt"
assert_allowed "terraform fmt -check" "terraform fmt -check"
assert_allowed "terraform show" "terraform show"
assert_allowed "terraform show with file" "terraform show tfplan"
assert_allowed "terraform output" "terraform output"
assert_allowed "terraform output specific" "terraform output vpc_id"
assert_allowed "terraform graph" "terraform graph"
assert_allowed "terraform providers" "terraform providers"
assert_allowed "terraform version" "terraform version"
assert_allowed "terraform get" "terraform get"
assert_allowed "terraform login" "terraform login"
assert_allowed "terraform logout" "terraform logout"
assert_allowed "terraform console" "terraform console"
assert_allowed "terraform test" "terraform test"
assert_allowed "terraform state list" "terraform state list"
assert_allowed "terraform state show" "terraform state show aws_instance.foo"
assert_allowed "terraform state pull" "terraform state pull"
assert_allowed "terraform workspace list" "terraform workspace list"
assert_allowed "terraform workspace show" "terraform workspace show"
assert_allowed "terraform workspace select" "terraform workspace select dev"
assert_allowed "tofu plan" "tofu plan"
assert_allowed "tofu init" "tofu init"
assert_allowed "tofu validate" "tofu validate"
assert_allowed "non-terraform command: ls" "ls -la"
assert_allowed "non-terraform command: npm test" "npm test"
assert_allowed "non-terraform command: git status" "git status"
assert_allowed "terraform plan chained with ls" "terraform plan && ls"
assert_allowed "ls chained with terraform plan" "ls && terraform plan"

# ── Blocked commands (exit 2) ───────────────────────────────────────────

printf '\nBlocked commands:\n'

assert_blocked "terraform apply" "terraform apply"
assert_blocked "terraform destroy" "terraform destroy"
assert_blocked "terraform apply -auto-approve" "terraform apply -auto-approve"
assert_blocked "terraform apply with plan file" "terraform apply tfplan"
assert_blocked "terraform import" "terraform import aws_instance.foo i-1234"
assert_blocked "terraform taint" "terraform taint aws_instance.foo"
assert_blocked "terraform untaint" "terraform untaint aws_instance.foo"
assert_blocked "terraform state rm" "terraform state rm aws_instance.foo"
assert_blocked "terraform state mv" "terraform state mv aws_instance.foo aws_instance.bar"
assert_blocked "terraform state push" "terraform state push"
assert_blocked "terraform force-unlock" "terraform force-unlock 12345"
assert_blocked "tofu apply" "tofu apply"
assert_blocked "tofu destroy" "tofu destroy"
assert_blocked "tofu import" "tofu import aws_instance.foo i-1234"
assert_blocked "env prefix: TF_VAR terraform apply" "TF_VAR_foo=bar terraform apply"
assert_blocked "chained: cd && terraform apply" "cd infra && terraform apply"
assert_blocked "chained: plan then apply" "terraform plan && terraform apply"
assert_blocked "chained with semicolon" "terraform plan ; terraform apply"
assert_blocked "chained with pipe" "echo yes | terraform apply"
assert_blocked "chained with or" "terraform plan || terraform apply"
assert_blocked "full path terraform" "/usr/local/bin/terraform apply"
assert_blocked "relative path terraform" "./terraform apply"
assert_blocked "unknown subcommand" "terraform newcmd"

# ── Edge cases ──────────────────────────────────────────────────────────

printf '\nEdge cases:\n'

assert_allowed "empty command" ""
assert_allowed "terraform as substring: terraforming" "terraforming plan"
assert_allowed "terraform in echo" "echo terraform apply"
assert_blocked "terraform alone (no subcommand)" "terraform"

# ── Summary ─────────────────────────────────────────────────────────────
printf '\n══════════════════════════════════════════\n'
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash hooks/terraform-guard-test.sh`
Expected: FAIL — `hooks/terraform-guard.sh` does not exist yet, script errors out.

- [ ] **Step 3: Commit the test**

```bash
git add hooks/terraform-guard-test.sh
git commit -m "test: add terraform-guard hook test cases"
```

---

### Task 2: Implement the terraform-guard hook script

**Files:**
- Create: `hooks/terraform-guard.sh`

- [ ] **Step 1: Create the hook script**

```bash
#!/bin/bash
# terraform-guard.sh — PreToolUse hook that blocks destructive terraform/tofu commands
#
# Allowlist approach: only known safe, read-only subcommands are permitted.
# Everything else is blocked (exit 2).
#
# Input: JSON on stdin from Claude Code PreToolUse hook
# Output: exit 0 (allow) or exit 2 + stderr message (block)
#
# Requires: jq, Bash 3.2+

set -euo pipefail

# ── Read command from stdin JSON ────────────────────────────────────────
INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || {
  # If jq fails or input is malformed, allow (don't block non-terraform work)
  exit 0
}

# Empty command — nothing to check
[ -z "$COMMAND" ] && exit 0

# ── Allowlist of safe subcommands ───────────────────────────────────────
# Single-word subcommands
SAFE_SINGLE="plan show graph init get login logout providers version validate fmt console test output"
# Two-word subcommands (state X, workspace X)
SAFE_STATE="list show pull"
SAFE_WORKSPACE="list show select"

is_safe_subcommand() {
  local subcmd="$1"
  local second="${2:-}"

  # Two-word subcommands: state/workspace + second word
  if [ "$subcmd" = "state" ] && [ -n "$second" ]; then
    for safe in $SAFE_STATE; do
      [ "$second" = "$safe" ] && return 0
    done
    return 1
  fi
  if [ "$subcmd" = "workspace" ] && [ -n "$second" ]; then
    for safe in $SAFE_WORKSPACE; do
      [ "$second" = "$safe" ] && return 0
    done
    return 1
  fi

  # Single-word subcommands
  for safe in $SAFE_SINGLE; do
    [ "$subcmd" = "$safe" ] && return 0
  done

  return 1
}

# ── Check a single command segment for terraform/tofu ───────────────────
check_segment() {
  local segment="$1"

  # Strip leading whitespace
  segment="${segment#"${segment%%[![:space:]]*}"}"

  # Skip env var prefixes (e.g., TF_VAR_foo=bar ...)
  while [[ "$segment" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    segment="${segment#*= }"
    segment="${segment#"${segment%%[![:space:]]*}"}"
  done

  # Extract the binary name (may be a path like /usr/local/bin/terraform)
  local binary
  binary=$(printf '%s' "$segment" | awk '{print $1}')
  local base
  base=$(basename "$binary" 2>/dev/null) || base="$binary"

  # Not terraform or tofu — allow
  if [ "$base" != "terraform" ] && [ "$base" != "tofu" ]; then
    return 0
  fi

  # Extract subcommand (word after binary) and second word
  local subcmd second
  subcmd=$(printf '%s' "$segment" | awk '{print $2}')
  second=$(printf '%s' "$segment" | awk '{print $3}')

  # No subcommand (bare "terraform") — block (ambiguous, could be aliased)
  if [ -z "$subcmd" ]; then
    return 1
  fi

  # Skip flags that appear before the subcommand (e.g., terraform -chdir=foo plan)
  while [[ "$subcmd" == -* ]]; do
    subcmd="$second"
    second=$(printf '%s' "$segment" | awk -v n="$(printf '%s' "$segment" | awk '{for(i=1;i<=NF;i++) if($i=="'"$subcmd"'") print i+1}')" '{print $n}')
    # If we run out of words, block
    [ -z "$subcmd" ] && return 1
  done

  is_safe_subcommand "$subcmd" "$second"
}

# ── Split command on shell separators and check each segment ────────────
# Replace separators with newlines, then check each segment
SEGMENTS=$(printf '%s' "$COMMAND" | sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g; s/|/\n/g')

while IFS= read -r segment; do
  [ -z "$segment" ] && continue
  if ! check_segment "$segment"; then
    # Extract what was blocked for the error message
    cat >&2 <<EOF
BLOCKED by terraform-guard: destructive terraform/tofu command detected.

Command: $COMMAND

Only read-only subcommands are allowed:
  plan, show, graph, init, get, login, logout, providers, version,
  validate, fmt, console, test, output,
  state list, state show, state pull,
  workspace list, workspace show, workspace select

To run destructive commands, execute them directly in your terminal.
EOF
    exit 2
  fi
done <<< "$SEGMENTS"

exit 0
```

- [ ] **Step 2: Make the script executable**

Run: `chmod +x hooks/terraform-guard.sh`

- [ ] **Step 3: Run the tests to verify they pass**

Run: `bash hooks/terraform-guard-test.sh`
Expected: All tests PASS.

- [ ] **Step 4: Commit the implementation**

```bash
git add hooks/terraform-guard.sh
git commit -m "feat: add terraform-guard hook — allowlist-based protection"
```

---

### Task 3: Register the hook in hooks.json

**Files:**
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Update hooks.json to add PreToolUse entry**

The current `hooks/hooks.json` has only a `SessionStart` hook. Add the `PreToolUse` section:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh"
          }
        ]
      }
    ],
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

- [ ] **Step 2: Run the tests again to confirm nothing broke**

Run: `bash hooks/terraform-guard-test.sh`
Expected: All tests still PASS.

- [ ] **Step 3: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat: register terraform-guard in hooks.json PreToolUse"
```

---

### Task 4: Write documentation

**Files:**
- Create: `hooks/TERRAFORM-GUARD.md`

- [ ] **Step 1: Create the documentation file**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add hooks/TERRAFORM-GUARD.md
git commit -m "docs: add terraform-guard hook documentation"
```
