#!/usr/bin/env bash
# Step 20 — Set the Conversational AI bot locale's Speech model to
# Speech-to-Speech / Amazon Nova Sonic, then build/activate the locale.
#
# Per the AWS docs (adminguide/nova-sonic-speech-to-speech.html), Nova Sonic is
# a per-locale "Speech model" setting on an existing Conversational AI bot, NOT
# a separate bot type. The S2S toggle is currently a console-only setting (no
# public CLI/API yet). This script just prints the exact console steps.
#
# NOTE: there is no longer a Bedrock "model access" prerequisite to check — AWS
# retired the Model access page; serverless foundation models auto-enable on
# first invocation across all commercial regions, and Connect manages its own
# Nova Sonic access regardless.
#
# Prereqs (see docs/RUNBOOK.md sec 0): instance on the full Connect Customer tier
# AND Lex Bot Management enabled (Console -> instance -> Flows -> Enable Lex Bot
# Management + Bot Analytics). Without the latter there is no Bots option on the
# admin-site Flows page.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require aws; require jq

REGION="$(aws_region)"
BOT_NAME="$(state_get bot_name)"
[ -n "$BOT_NAME" ] || die "Run 10-create-bot.sh first (no bot recorded)."

log "Bedrock model access is auto-enabled (the Model access page was retired);"
log "Connect manages Nova Sonic access itself. No pre-check needed in $REGION."

printf '\n----------------------------------------------------------------------\n'
printf 'Manual step (docs/RUNBOOK.md, "Enable Nova Sonic Speech-to-Speech"):\n\n'
printf '  Bot: %s  -> Connect admin site -> Configuration tab -> en-US locale\n' "$BOT_NAME"
printf '  1. Speech model section -> Edit\n'
printf '  2. Model type:  Speech-to-Speech\n'
printf '  3. Voice provider:  Amazon Nova Sonic  -> Confirm\n'
printf '  4. If "Unbuilt changes" appears -> Build language; wait until Active\n\n'
printf 'In the flow Set voice block we already set: Matthew / Generative / en-US\n'
printf -- '----------------------------------------------------------------------\n\n'

read -r -p "Press Enter once the locale build is Active... " _
state_set nova_sonic_enabled "true"
log "Marked Nova Sonic S2S as enabled."
