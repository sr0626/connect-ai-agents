#!/usr/bin/env bash
# Step 40 — Patch the published contact flow with the real bot alias ARN and set
# it as the inbound flow for the claimed DID.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require aws; require jq

REGION="$(aws_region)"
INSTANCE_ID="$(tf_out connect_instance_id)"
FLOW_ID="$(tf_out inbound_flow_id)"
QUEUE_ARN="$(tf_out escalation_queue_arn)"
PHONE_ID="$(tf_out phone_number_id || true)"
BOT_ALIAS_ARN="$(state_get bot_alias_arn)"
[ -n "$BOT_ALIAS_ARN" ] || die "No bot alias ARN recorded (run 10-create-bot.sh)."

# --- Render the flow JSON with the real values, then update the flow ----------
log "Rendering flow content with bot alias ARN ..."
content="$(sed -e "s|\${bot_alias_arn}|${BOT_ALIAS_ARN}|g" \
              -e "s|\${escalation_queue_arn}|${QUEUE_ARN}|g" \
              "$ROOT_DIR/flows/inbound-ai-agent.json.tpl")"

# Validate JSON before sending.
echo "$content" | jq empty || die "Rendered flow is not valid JSON."

log "Updating contact flow $FLOW_ID with the full AI-agent flow ..."
if AWSCLI connect update-contact-flow-content \
     --instance-id "$INSTANCE_ID" \
     --contact-flow-id "$FLOW_ID" \
     --content "$content" 2>/tmp/flowupdate.err; then
  log "Flow content updated."
else
  warn "Connect rejected the AI-agent flow content:"
  sed 's/^/    /' /tmp/flowupdate.err >&2 || true
  warn "The minimal greeting flow created by Terraform is still in place."
  warn "Finish the flow in the console (docs/RUNBOOK.md, step 5): open the"
  warn "  inbound flow, drop a 'Get customer input' block, enable the AI agent /"
  warn "  select your bot, wire escalate -> Transfer to queue and error/timeout"
  warn "  -> Disconnect, then Save + Publish."
  warn "The exact JSON for the new AI-agent block varies; the console block is"
  warn "the reliable path. Continuing so the number can still be associated."
fi

# --- Associate the flow with the claimed inbound number ----------------------
if [ -n "$PHONE_ID" ] && [ "$PHONE_ID" != "None" ]; then
  log "Associating flow with phone number $PHONE_ID ..."
  AWSCLI connect associate-phone-number-contact-flow \
    --phone-number-id "$PHONE_ID" \
    --instance-id "$INSTANCE_ID" \
    --contact-flow-id "$FLOW_ID" || \
    warn "Could not auto-associate the number; set the inbound flow in the console."
else
  warn "No claimed phone number; associate the inbound flow with a number manually."
fi

log "Flow wired. Call the DID to test the Nova Sonic self-service agent."
