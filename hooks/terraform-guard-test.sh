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
