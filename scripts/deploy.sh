#!/usr/bin/env bash
# One-shot deploy: terraform apply, then the wiring steps 10 -> 40.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require terraform; require aws; require jq

log "terraform init + apply ..."
terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" apply -auto-approve

bash "$ROOT_DIR/scripts/10-create-bot.sh"
bash "$ROOT_DIR/scripts/20-enable-nova-sonic.sh"
bash "$ROOT_DIR/scripts/30-create-ai-agent.sh"
bash "$ROOT_DIR/scripts/40-wire-flow.sh"

log "Done. Test number:"
terraform -chdir="$TF_DIR" output -raw phone_number || true
echo
