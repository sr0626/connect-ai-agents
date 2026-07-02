#!/usr/bin/env bash
# Teardown: remove EVERYTHING this project creates.
#
#   1. Script-created Q-in-Connect resources (AI agents, AI prompts, assistant)
#      and the instance integration association  -- via CLI.
#   2. The Conversational AI bot from step 10    -- requires console deletion
#      (no stable delete API); this script gates terraform destroy until you
#      confirm it's gone, so the Connect instance can actually be removed.
#   3. All Terraform-managed infra                -- via terraform destroy.
#
# Idempotent and best-effort: resources are discovered by name if the local
# state file (scripts/.state.json) is missing or incomplete. Set
# CONFIRM_BOT_DELETED=1 to skip the interactive bot gate (CI/non-interactive).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require terraform; require aws; require jq

REGION="$(aws_region)"
INSTANCE_ID="$(tf_out connect_instance_id || true)"
PROJECT_NAME="$(tf_out connect_instance_alias || true)"
ASSISTANT_NAME="${PROJECT_NAME}-assistant"

# --- 1. Q in Connect resources ----------------------------------------------
if aws qconnect help >/dev/null 2>&1; then
  # Resolve the assistant id from state first, else discover it by name.
  assistant_id="$(state_get assistant_id || true)"
  if [ -z "$assistant_id" ] && [ -n "$PROJECT_NAME" ]; then
    assistant_id="$(AWSCLI qconnect list-assistants \
      --query "assistantSummaries[?name=='${ASSISTANT_NAME}'].assistantId | [0]" \
      --output text 2>/dev/null || true)"
  fi

  if [ -n "$assistant_id" ] && [ "$assistant_id" != "None" ]; then
    assistant_arn="$(AWSCLI qconnect get-assistant --assistant-id "$assistant_id" \
      --query 'assistant.assistantArn' --output text 2>/dev/null || true)"

    # Delete the instance<->assistant association first (else the Connect
    # instance can't be destroyed). Delete all WISDOM_ASSISTANT associations.
    if [ -n "$INSTANCE_ID" ]; then
      assoc_ids="$(AWSCLI connect list-integration-associations \
        --instance-id "$INSTANCE_ID" --integration-type WISDOM_ASSISTANT \
        --query 'IntegrationAssociationSummaryList[].IntegrationAssociationId' \
        --output text 2>/dev/null || true)"
      for assoc_id in $assoc_ids; do
        AWSCLI connect delete-integration-association \
          --instance-id "$INSTANCE_ID" --integration-association-id "$assoc_id" || true
        log "Removed integration association $assoc_id"
      done
    fi

    # Delete all AI agents, then AI prompts, then the assistant itself.
    agent_ids="$(AWSCLI qconnect list-ai-agents --assistant-id "$assistant_id" \
      --query 'aiAgentSummaries[].aiAgentId' --output text 2>/dev/null || true)"
    for id in $agent_ids; do
      AWSCLI qconnect delete-ai-agent --assistant-id "$assistant_id" --ai-agent-id "$id" || true
      log "Deleted AI agent $id"
    done

    prompt_ids="$(AWSCLI qconnect list-ai-prompts --assistant-id "$assistant_id" \
      --query 'aiPromptSummaries[].aiPromptId' --output text 2>/dev/null || true)"
    for id in $prompt_ids; do
      AWSCLI qconnect delete-ai-prompt --assistant-id "$assistant_id" --ai-prompt-id "$id" || true
      log "Deleted AI prompt $id"
    done

    # Delete any AI guardrails (RUNBOOK §11, created by scripts/guardrail.sh).
    guardrail_ids="$(AWSCLI qconnect list-ai-guardrails --assistant-id "$assistant_id" \
      --query 'aiGuardrailSummaries[].aiGuardrailId' --output text 2>/dev/null || true)"
    for id in $guardrail_ids; do
      AWSCLI qconnect delete-ai-guardrail --assistant-id "$assistant_id" --ai-guardrail-id "$id" || true
      log "Deleted AI guardrail $id"
    done

    # Detach any knowledge base associated to the assistant (the policy-Q&A KB
    # from RUNBOOK §7), else delete-assistant fails. The KB itself is account-
    # level (deleted further below); here we just remove the association.
    kb_assoc_ids="$(AWSCLI qconnect list-assistant-associations --assistant-id "$assistant_id" \
      --query 'assistantAssociationSummaries[].assistantAssociationId' --output text 2>/dev/null || true)"
    for id in $kb_assoc_ids; do
      AWSCLI qconnect delete-assistant-association \
        --assistant-id "$assistant_id" --assistant-association-id "$id" || true
      log "Removed assistant association $id"
    done

    AWSCLI qconnect delete-assistant --assistant-id "$assistant_id" || true
    log "Deleted assistant $assistant_id"
  else
    log "No Q-in-Connect assistant found (nothing to delete)."
  fi

  # Delete the policy-Q&A knowledge base(s) — account-level (RUNBOOK §7), so
  # handled independently of the assistant. Named like the project; safe no-op
  # if none exist. (The S3 bucket + document are Terraform-managed and removed
  # by the terraform destroy below.)
  if [ -n "$PROJECT_NAME" ]; then
    kb_ids="$(AWSCLI qconnect list-knowledge-bases \
      --query "knowledgeBaseSummaries[?contains(name, '${PROJECT_NAME}')].knowledgeBaseId" \
      --output text 2>/dev/null || true)"
    for id in $kb_ids; do
      AWSCLI qconnect delete-knowledge-base --knowledge-base-id "$id" || true
      log "Deleted knowledge base $id"
    done
  fi
fi

# --- 2. Conversational AI bot (manual) --------------------------------------
bot_name="$(state_get bot_name || true)"
bot_alias_arn="$(state_get bot_alias_arn || true)"
if [ "${CONFIRM_BOT_DELETED:-0}" != "1" ]; then
  printf '\n----------------------------------------------------------------------\n'
  printf 'Manual step: delete the Conversational AI bot before continuing.\n'
  printf '  Connect admin site -> Bots -> delete: %s\n' "${bot_name:-<your bot>}"
  [ -n "$bot_alias_arn" ] && printf '  (alias ARN: %s)\n' "$bot_alias_arn"
  printf 'The Connect instance cannot be destroyed while a bot is attached.\n'
  printf -- '----------------------------------------------------------------------\n'
  read -r -p "Type 'deleted' once the bot is removed (or 'skip' to proceed anyway): " ans
  case "$ans" in
    deleted) log "Bot confirmed deleted." ;;
    skip)    warn "Skipping bot gate; terraform destroy may fail if a bot remains." ;;
    *)       die "Aborting teardown. Re-run after deleting the bot." ;;
  esac
fi

# --- 3. Terraform-managed infra ---------------------------------------------
log "terraform destroy ..."
terraform -chdir="$TF_DIR" destroy -auto-approve

rm -f "$STATE_FILE"
log "Teardown complete. Verify in the console that the Connect instance, bot,"
log "and Q-in-Connect assistant are all gone."
