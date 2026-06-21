#!/usr/bin/env bash
# Step 30 — Create the Amazon Q in Connect AI agent (self-service) that powers
# the bot's reasoning, from prompts/agent-instructions.md, and register the two
# tool Lambdas as actions.
#
# Uses the `aws qconnect` API family (create-assistant / create-ai-prompt /
# create-ai-guardrail / create-ai-agent). Exact request shapes differ across
# aws-cli versions; where a call isn't available the script records what it can
# and points at docs/RUNBOOK.md to finish in the console.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require aws; require jq

REGION="$(aws_region)"
PROJECT_NAME="$(tf_out connect_instance_alias)"
AGENT_DISPLAY_NAME="$(tf_out agent_name)"
INSTANCE_ID="$(tf_out connect_instance_id)"
PROMPT_FILE="$ROOT_DIR/prompts/agent-instructions.md"
[ -f "$PROMPT_FILE" ] || die "Missing $PROMPT_FILE"

if ! aws qconnect help >/dev/null 2>&1; then
  warn "Your aws-cli has no 'qconnect' command. Upgrade aws-cli, or create the"
  warn "AI agent in the console (docs/RUNBOOK.md, 'Create the AI agent')."
  printf 'Press Enter once the AI agent is created in the console... '
  read -r _
  state_set ai_agent_done "manual"
  exit 0
fi

# --- 1. Assistant (Amazon Q in Connect domain) -- idempotent by name ---------
ASSISTANT_NAME="${PROJECT_NAME}-assistant"
assistant_id="$(state_get assistant_id || true)"
if [ -z "$assistant_id" ]; then
  assistant_id="$(AWSCLI qconnect list-assistants \
    --query "assistantSummaries[?name=='${ASSISTANT_NAME}'].assistantId | [0]" \
    --output text 2>/dev/null || true)"
fi
if [ -z "$assistant_id" ] || [ "$assistant_id" = "None" ]; then
  log "Creating Q in Connect assistant: $ASSISTANT_NAME"
  assistant_id="$(AWSCLI qconnect create-assistant \
    --name "$ASSISTANT_NAME" --type AGENT \
    --query 'assistant.assistantId' --output text)"
fi
state_set assistant_id "$assistant_id"
log "Assistant: $assistant_id"

# Assistant ARN is needed to associate it with the Connect instance.
assistant_arn="$(AWSCLI qconnect get-assistant --assistant-id "$assistant_id" \
  --query 'assistant.assistantArn' --output text)"
state_set assistant_arn "$assistant_arn"

# --- 1b. Enable Amazon Q in Connect on the instance (the "AI agent" switch) ---
# This WISDOM_ASSISTANT integration association is what turns AI agents on for
# the Connect instance. Idempotent: skip if an association already exists.
existing_assoc="$(AWSCLI connect list-integration-associations \
  --instance-id "$INSTANCE_ID" --integration-type WISDOM_ASSISTANT \
  --query "IntegrationAssociationSummaryList[?IntegrationArn=='${assistant_arn}'].IntegrationAssociationId | [0]" \
  --output text 2>/dev/null || true)"
if [ -z "$existing_assoc" ] || [ "$existing_assoc" = "None" ]; then
  log "Associating assistant with the instance (enabling AI agents) ..."
  AWSCLI connect create-integration-association \
    --instance-id "$INSTANCE_ID" \
    --integration-type WISDOM_ASSISTANT \
    --integration-arn "$assistant_arn" >/dev/null
else
  log "AI agents already enabled on the instance (assoc $existing_assoc)."
fi

# --- 2. AI prompt from the instructions file ---------------------------------
PROMPT_NAME="${PROJECT_NAME}-self-service-prompt"
prompt_text="$(cat "$PROMPT_FILE")"
ai_prompt_id="$(state_get ai_prompt_id || true)"
if [ -z "$ai_prompt_id" ]; then
  log "Creating AI prompt: $PROMPT_NAME"
  # The template content is passed as a text blob the agent uses as system text.
  template_json="$(jq -n --arg t "$prompt_text" \
    '{textFullAIPromptEditTemplateConfiguration: {text: $t}}')"
  if ai_prompt_id="$(AWSCLI qconnect create-ai-prompt \
      --assistant-id "$assistant_id" \
      --name "$PROMPT_NAME" \
      --type SELF_SERVICE_ANSWER_GENERATION \
      --api-format MESSAGES \
      --model-id "anthropic.claude-3-haiku-20240307-v1:0" \
      --template-type TEXT \
      --template-configuration "$template_json" \
      --visibility-status PUBLISHED \
      --query 'aiPrompt.aiPromptId' --output text 2>/tmp/aiprompt.err)"; then
    state_set ai_prompt_id "$ai_prompt_id"
    log "AI prompt: $ai_prompt_id"
  else
    warn "create-ai-prompt failed (request shape varies by cli version):"
    sed 's/^/    /' /tmp/aiprompt.err >&2 || true
    warn "Create the AI prompt + agent in the console (docs/RUNBOOK.md)."
    state_set ai_agent_done "manual"
    exit 0
  fi
fi

# --- 3. Self-service AI agent ------------------------------------------------
AGENT_NAME="$AGENT_DISPLAY_NAME"
ai_agent_id="$(state_get ai_agent_id || true)"
if [ -z "$ai_agent_id" ]; then
  log "Creating self-service AI agent: $AGENT_NAME"
  agent_cfg="$(jq -n --arg p "$ai_prompt_id" \
    '{selfServiceAIAgentConfiguration: {selfServiceAnswerGenerationAIPromptId: $p}}')"
  if ai_agent_id="$(AWSCLI qconnect create-ai-agent \
      --assistant-id "$assistant_id" \
      --name "$AGENT_NAME" \
      --type SELF_SERVICE \
      --visibility-status PUBLISHED \
      --configuration "$agent_cfg" \
      --query 'aiAgent.aiAgentId' --output text 2>/tmp/aiagent.err)"; then
    state_set ai_agent_id "$ai_agent_id"
    log "AI agent: $ai_agent_id"
  else
    warn "create-ai-agent failed:"
    sed 's/^/    /' /tmp/aiagent.err >&2 || true
    warn "Finish in the console (docs/RUNBOOK.md, 'Create the AI agent')."
    state_set ai_agent_done "manual"
    exit 0
  fi
fi

printf '\nNOTE: Registering the order-lookup / refund Lambdas as AI-agent tools/actions\n'
printf 'is configured under the bot (Actions) — see docs/RUNBOOK.md "Attach tools".\n'
printf 'Tool Lambda ARNs:\n'
terraform -chdir="$TF_DIR" output -json tool_lambda_arns | jq -r 'to_entries[] | "  \(.key): \(.value)"'

state_set ai_agent_done "true"
log "AI agent step complete."
