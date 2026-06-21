#!/usr/bin/env bash
# Step 10 — Create the Conversational AI bot (next-gen Connect) + en-US locale.
#
# NOTE: The next-gen "Conversational AI bot" used by Nova Sonic agentic
# self-service is very new and does not have a stable, documented public CLI/API
# at the time of writing. This script (a) detects whether your aws-cli exposes
# the API and uses it if so, otherwise (b) prints the console steps from
# docs/RUNBOOK.md and asks you to paste back the resulting bot alias ARN, which
# it stores for later steps.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require aws; require jq

INSTANCE_ID="$(tf_out connect_instance_id)"
BOT_NAME="$(tf_out agent_name)"
log "Connect instance: $INSTANCE_ID"

# A previously captured ARN is shown at the prompt below so it can be kept
# (press Enter) or corrected (paste a new value).
existing="$(state_get bot_alias_arn || true)"

# Probe for a CLI surface. These op names may change as the feature GAs.
if aws connect help 2>/dev/null | grep -qiE 'create-bot|create-conversational'; then
  warn "Detected a Connect bot CLI surface. Review scripts/10-create-bot.sh and"
  warn "fill in the exact create-bot call for your aws-cli version, then re-run."
  warn "Falling through to manual capture for now."
fi

printf '\n----------------------------------------------------------------------\n'
printf 'Manual step (see docs/RUNBOOK.md, "Create the Conversational AI bot"):\n\n'
printf '  1. Connect admin site -> Bots -> Create bot\n'
printf '       Name: %s\n' "$BOT_NAME"
printf '  2. Add locale: English (US) / en-US\n'
printf '  3. Add at least one intent (e.g. a fallback) so the locale can build.\n'
printf '  4. Save. (Nova Sonic + AI-agent wiring happen in steps 20 and 30.)\n\n'
printf 'Then paste the bot ALIAS ARN below. A next-gen Connect bot is a Lex V2\n'
printf 'bot, so use the LEX alias ARN (ids, not names):\n'
printf '  arn:aws:lex:REGION:ACCOUNT:bot-alias/<botId>/<botAliasId>\n'
printf 'Get it with:\n'
printf '  aws lexv2-models list-bots --region %s --query "botSummaries[?botName==\\\`%s\\\`].botId"\n' "$(aws_region)" "$BOT_NAME"
printf '  aws lexv2-models list-bot-aliases --region %s --bot-id <botId>\n' "$(aws_region)"
printf -- '----------------------------------------------------------------------\n\n'

if [ -n "$existing" ]; then
  printf 'Currently recorded: %s\n' "$existing"
  read -r -p "Bot alias ARN (Enter to keep current, or paste a new value): " BOT_ALIAS_ARN
  BOT_ALIAS_ARN="${BOT_ALIAS_ARN:-$existing}"
else
  read -r -p "Bot alias ARN: " BOT_ALIAS_ARN
fi

[ -n "$BOT_ALIAS_ARN" ] || die "No bot alias ARN provided."
state_set bot_alias_arn "$BOT_ALIAS_ARN"
state_set bot_name "$BOT_NAME"
if [ "$BOT_ALIAS_ARN" = "$existing" ]; then
  log "Kept existing bot alias ARN."
else
  log "Recorded bot alias ARN: $BOT_ALIAS_ARN"
fi
