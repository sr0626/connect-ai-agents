#!/usr/bin/env bash
# Create / delete the Amplifier AI Guardrail on the Q-in-Connect assistant.
#
# WHY a script (not Terraform): the guardrail is a native Amazon Q in Connect
# ("qconnect") resource. The awscc / Cloud Control AWS::Wisdom::AIGuardrail
# handler fails server-side ("GeneralServiceException"), while this direct
# qconnect API path creates the exact same config cleanly. This matches the rest
# of the agentic layer (assistant, AI agent, KB integration) which is also
# console/CLI-managed, not Terraform. See docs/RUNBOOK.md §11.
#
# Usage:
#   scripts/guardrail.sh create   # create it (idempotent — skips if it exists)
#   scripts/guardrail.sh delete    # remove it (teardown; also frees quota)
#   scripts/guardrail.sh status    # print its id/arn if present
#
# Policy areas: denied topics (no legal/medical/financial advice, no competitor
# talk), sensitive-info/PII (block spoken card/CVV/SSN/bank/PIN — NOT order
# id/phone, the bot needs those), and profanity + harmful-content/prompt-injection
# filters.
#
# NOTE: NO contextual-grounding policy here — Amplifier is an ORCHESTRATION agent,
# and Connect rejects a grounding policy on orchestration agents ("Contextual
# grounding guardrail policy is not allowed for ORCHESTRATION AIAgent"). Grounding
# only applies to answer-recommendation/retrieval agents. No-hallucination for
# policy Q&A is instead enforced by the Retrieve tool's "answer only from the
# returned content" instruction (RUNBOOK §7).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require aws; require jq

REGION="$(aws_region)"
PROJECT_NAME="$(tf_out connect_instance_alias || true)"
[ -n "$PROJECT_NAME" ] || die "Could not read connect_instance_alias from terraform output."
ASSISTANT_NAME="${PROJECT_NAME}-assistant"
GUARDRAIL_NAME="${PROJECT_NAME}-guardrail"

# Resolve the assistant id: state file first, else discover by name.
assistant_id="$(state_get assistant_id || true)"
if [ -z "$assistant_id" ] || [ "$assistant_id" = "None" ]; then
  assistant_id="$(AWSCLI qconnect list-assistants \
    --query "assistantSummaries[?name=='${ASSISTANT_NAME}'].assistantId | [0]" \
    --output text 2>/dev/null || true)"
fi
[ -n "$assistant_id" ] && [ "$assistant_id" != "None" ] \
  || die "Could not find assistant '${ASSISTANT_NAME}'. Is the instance up?"

guardrail_id() {
  AWSCLI qconnect list-ai-guardrails --assistant-id "$assistant_id" \
    --query "aiGuardrailSummaries[?name=='${GUARDRAIL_NAME}'].aiGuardrailId | [0]" \
    --output text 2>/dev/null | sed 's/^None$//'
}

case "${1:-}" in
  create)
    if [ -n "$(guardrail_id)" ]; then
      log "Guardrail '${GUARDRAIL_NAME}' already exists ($(guardrail_id)) — nothing to do."
      exit 0
    fi
    log "Creating guardrail '${GUARDRAIL_NAME}' on assistant ${assistant_id} ..."
    AWSCLI qconnect create-ai-guardrail \
      --assistant-id "$assistant_id" --name "$GUARDRAIL_NAME" \
      --visibility-status PUBLISHED \
      --blocked-input-messaging "Sorry, I can't help with that. I can assist with your orders, refunds, and our return policy." \
      --blocked-outputs-messaging "Sorry, I'm not able to share that. I can help with your orders, refunds, and our return policy." \
      --content-policy-config '{"filtersConfig":[{"type":"HATE","inputStrength":"HIGH","outputStrength":"HIGH"},{"type":"INSULTS","inputStrength":"HIGH","outputStrength":"HIGH"},{"type":"SEXUAL","inputStrength":"HIGH","outputStrength":"HIGH"},{"type":"VIOLENCE","inputStrength":"MEDIUM","outputStrength":"MEDIUM"},{"type":"MISCONDUCT","inputStrength":"MEDIUM","outputStrength":"MEDIUM"},{"type":"PROMPT_ATTACK","inputStrength":"HIGH","outputStrength":"NONE"}]}' \
      --word-policy-config '{"managedWordListsConfig":[{"type":"PROFANITY"}]}' \
      --sensitive-information-policy-config '{"piiEntitiesConfig":[{"type":"CREDIT_DEBIT_CARD_NUMBER","action":"BLOCK"},{"type":"CREDIT_DEBIT_CARD_CVV","action":"BLOCK"},{"type":"CREDIT_DEBIT_CARD_EXPIRY","action":"BLOCK"},{"type":"US_SOCIAL_SECURITY_NUMBER","action":"BLOCK"},{"type":"US_BANK_ACCOUNT_NUMBER","action":"BLOCK"},{"type":"PIN","action":"BLOCK"}]}' \
      --topic-policy-config '{"topicsConfig":[{"name":"Legal Advice","type":"DENY","definition":"Requests for legal opinions, interpretation of laws or contracts, or how to pursue legal action.","examples":["Can I sue you for a late delivery?"]},{"name":"Medical Advice","type":"DENY","definition":"Requests for medical, health, diagnosis, or treatment guidance.","examples":["Is this supplement safe with my medication?"]},{"name":"Financial or Investment Advice","type":"DENY","definition":"Requests for investment, tax, or personal financial-planning advice unrelated to an order or refund.","examples":["Should I invest my refund in stocks?"]},{"name":"Competitor Discussion","type":"DENY","definition":"Requests to compare, recommend, or discuss competing retailers or their products and prices.","examples":["Is a competitor cheaper than you?"]}]}' \
      >/dev/null
    gid="$(guardrail_id)"
    log "Created. Guardrail id: ${gid}"
    log "Next: AI agent designer -> Amplifier -> set AI Guardrail = '${GUARDRAIL_NAME}' -> Publish (RUNBOOK §11)."
    ;;

  delete)
    gid="$(guardrail_id)"
    if [ -n "$gid" ]; then
      AWSCLI qconnect delete-ai-guardrail --assistant-id "$assistant_id" --ai-guardrail-id "$gid"
      log "Deleted guardrail '${GUARDRAIL_NAME}' ($gid). Remember to remove it from Amplifier + Publish."
    else
      log "Guardrail '${GUARDRAIL_NAME}' not found — nothing to delete."
    fi
    ;;

  status)
    gid="$(guardrail_id)"
    if [ -n "$gid" ]; then
      log "Guardrail '${GUARDRAIL_NAME}': ${gid}"
    else
      log "Guardrail '${GUARDRAIL_NAME}' does not exist."
    fi
    ;;

  *)
    die "usage: $(basename "$0") {create|delete|status}"
    ;;
esac
