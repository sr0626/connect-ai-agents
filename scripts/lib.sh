#!/usr/bin/env bash
# Shared helpers for the wiring scripts. Sourced, not executed directly.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"
STATE_FILE="$ROOT_DIR/scripts/.state.json"

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required tool: $1"
}

# Read a single Terraform output value.
tf_out() {
  terraform -chdir="$TF_DIR" output -raw "$1" 2>/dev/null
}

# region/profile flags for aws cli, derived from Terraform.
aws_region() { tf_out region; }
AWSCLI() { aws --region "$(aws_region)" "$@"; }

# --- tiny key/value state store (so steps can pass ids to each other) --------
state_init() { [ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE"; }

state_set() { # state_set KEY VALUE
  state_init
  tmp="$(mktemp)"
  jq --arg k "$1" --arg v "$2" '.[$k]=$v' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

state_get() { # state_get KEY -> value or empty
  state_init
  jq -r --arg k "$1" '.[$k] // empty' "$STATE_FILE"
}
