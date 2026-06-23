# Future enhancements (backlog)

Ideas beyond the core demo (Nova Sonic voice → orchestrator → order_lookup / process_refund /
escalate). Three have shipped; what's left is open backlog.

## ✅ Completed
- **Knowledge base — policy Q&A.** Amplifier answers free-form return/refund policy questions via the
  built-in **`Retrieve`** tool against an S3-sourced Q-in-Connect knowledge base. Infra in
  `terraform/s3-kb.tf` (bucket + `app-integrations` read policy + the policy PDF); console wiring in
  **[RUNBOOK §7](RUNBOOK.md)**. Source doc: `docs/return-refund-policy.txt` → `…-policy.pdf`.
- **ANI caller-ID lookup.** `order_lookup` falls back to the caller's own number
  (`Details.ContactData.CustomerEndpoint.Address`, via `_caller_ani`) when no order_id/phone is given.
  The agent first **confirms** ("use the number you're calling from, or a different one?") before using
  it — gating + confirmation live in the order_lookup tool Instructions. No flow wiring needed.
- **Observability — "debugging a call".** A layered guide (Contact search → AI agent trace/transcript
  via Contact Lens → flow logs → Lambda `EVENT/PARAMS/RESULT` → Lex logs) with a symptom→layer triage
  table. **[RUNBOOK §8](RUNBOOK.md)**.

## Open backlog

### 1. Order cancellation tool
A `cancel_order` flow-module tool (Lambda) to cancel an order while it's still `processing`/`shipped`,
complementing refunds. Same pattern as `process_refund` (flat response + spoken `message`,
idempotent, eligibility by status).

### 2. Multi-document knowledge base
Add more policy docs (shipping, warranty) and segment retrieval with **multiple Retrieve tools** so
the agent picks the right source per question. See the AWS guide on configuring multiple retrieve
tools for content segmentation.
