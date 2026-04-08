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
#
# Limitations:
# - Does not detect terraform invoked via bash -c, eval, or command substitution
# - Does not handle nested subshells or process substitution
# - This hook is a safety net, not a security sandbox

set -euo pipefail

# ── Read command from stdin JSON ────────────────────────────────────────
INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || {
  # If jq fails or input is malformed, allow (don't block non-terraform work)
  exit 0
}

# Only inspect Bash tool invocations; allow everything else through
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
[ "$TOOL_NAME" = "Bash" ] || exit 0

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
    # Remove the first word (VAR=value) by removing everything up to the first space
    # If there's no space, the whole thing is consumed
    if [[ "$segment" == *" "* ]]; then
      segment="${segment#* }"
    else
      segment=""
    fi
    # Strip leading whitespace
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
    # Shift words: subcmd becomes second, second becomes next word
    local rest
    rest=$(printf '%s' "$segment" | awk -v target="$subcmd" '{found=0; for(i=1;i<=NF;i++){if(found){for(j=i;j<=NF;j++) printf "%s ", $j; break} if($i==target) found=1}}')
    subcmd=$(printf '%s' "$rest" | awk '{print $1}')
    second=$(printf '%s' "$rest" | awk '{print $2}')
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
