# Future enhancements (backlog)

Ideas beyond the core demo (Nova Sonic voice → orchestrator → order_lookup / process_refund /
escalate). The first two have shipped; what's left is open backlog.

## ✅ Completed
- **Knowledge base — policy Q&A.** Amplifier answers free-form return/refund policy questions via the
  built-in **`Retrieve`** tool against an S3-sourced Q-in-Connect knowledge base. Infra in
  `terraform/s3-kb.tf` (bucket + `app-integrations` read policy + the policy PDF); console wiring in
  **[RUNBOOK §7](RUNBOOK.md)**. Source doc: `docs/return-refund-policy.txt` → `…-policy.pdf`.
- **ANI caller-ID lookup.** `order_lookup` falls back to the caller's own number
  (`Details.ContactData.CustomerEndpoint.Address`, via `_caller_ani`) when no order_id/phone is given.
  The agent first **confirms** ("use the number you're calling from, or a different one?") before using
  it — gating + confirmation live in the order_lookup tool Instructions. No flow wiring needed.

## Open backlog

*Priority order — observability is next up.*

### 1. Observability / "debugging a call" doc  ⭐ top priority
A RUNBOOK section on reconstructing a call's journey: Contact search → transcript (Bot Analytics &
Transcripts is enabled); enable Lex conversation logs on the bot alias → CloudWatch/S3; flow logs
(`/aws/connect/...`, showing `GetUserInput=Amazonqinconnect` + the `Tool` attribute check); the
Lambda `EVENT/PARAMS/RESULT` logging that's already in place. Note: the agent's system prompt is the
static orchestration prompt — there is no per-call chain-of-thought log.

### 2. Order cancellation tool
A `cancel_order` flow-module tool (Lambda) to cancel an order while it's still `processing`/`shipped`,
complementing refunds. Same pattern as `process_refund` (flat response + spoken `message`,
idempotent, eligibility by status).

### 3. Multi-document knowledge base
Add more policy docs (shipping, warranty) and segment retrieval with **multiple Retrieve tools** so
the agent picks the right source per question. See the AWS guide on configuring multiple retrieve
tools for content segmentation.
