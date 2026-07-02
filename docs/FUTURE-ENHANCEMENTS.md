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
- **AI Guardrails.** Native Q-in-Connect AI Guardrail on the Amplifier agent covering denied topics (no
  legal/medical/financial advice), PII (block spoken card/SSN/bank/PIN), and profanity + prompt-injection
  filters. (Contextual grounding is **not** allowed on orchestration agents, so no-hallucination stays the
  Retrieve tool's job — §7.) Created via **`scripts/guardrail.sh`** (qconnect API) — *not* Terraform: the
  `awscc`/Cloud Control `AWS::Wisdom::AIGuardrail` handler fails server-side. Attach + demo in
  **[RUNBOOK §11](RUNBOOK.md)**.

## Open backlog — prioritized for a management demo

Ordered by **wow-per-effort** and how much each leans on what's already built. Effort: 🟢 small ·
🟡 medium · 🔴 heavy. "Uses what we have" = mostly config / small additions on existing assets.

### P1 — quick wins, biggest live "wow" (do first)
1. **Personalized greeting (ANI).** 🟢 🚧 *In progress.* Greet a known caller by **first name** at call
   start: *"Hi Sateesh, thanks for calling …"*. **Built:** `customers` profile table (phone → first/last
   name) + `customer_lookup` Lambda that composes the greeting from the caller's ANI — see
   **[RUNBOOK §9](RUNBOOK.md)**. **Pending:** `terraform apply` + flow wiring (invoke the Lambda at call
   start, play `$.External.greeting`). **Stretch:** pass the name to the agent and proactively reference
   the caller's latest order (*"…I see your Smart Watch shipped yesterday — calling about that?"*).
2. **Warm handoff with an AI summary.** 🟢 *Nearly free.* On Escalate, populate a one-line conversation
   summary + order context into a contact attribute so the human agent gets a screen-pop and the caller
   never repeats themselves. The Escalate Return-to-Control tool already carries input params — just set
   + display them.
### Next up — prioritized after guardrails (2026-07-01)
The immediate `main`-project priorities, ahead of the P2/P3 items below.
A. **Enable Customer Profiles.** 🟡 Turn on Amazon Connect **Customer Profiles**: a native domain that
   unifies caller identity + contact history (and can ingest orders) into a profile surfaced to agents
   and usable from flows/Lambda. Natural upgrade from the custom `customers` DynamoDB table +
   `customer_lookup` Lambda — could back the personalized greeting (#1) and order lookup with native
   profiles / calculated attributes. Terraform: `aws_customerprofiles_domain` (+ object types /
   integrations).
B. **Third-party app to manage the instance, governed by Connect security profiles.** 🔴 An app whose
   access is authorized by **Connect security-profile permissions**, exposing operational toggles for
   the instance. **Start with: switch the flow's TTS voice** (e.g. store the chosen Nova Sonic voice in
   a config the flow reads *dynamically* — replacing today's static Set-voice block — and let the app
   write it). Scales to more instance-management toggles later. Bigger lift: new app + auth + the
   dynamic-voice flow change.

### P2 — high management value (ROI + tangible actions)
4. **Live containment dashboard.** 🟡 QuickSight/CloudWatch view over Contact Lens data: calls handled,
   **% self-service deflection**, top intents, avg handle time, sentiment, escalation rate. The single
   most persuasive artifact in an exec room — the number that says *"this deflected N% of calls."*
5. **SMS the return label / order link mid-call.** 🟡 *"I just texted you the prepaid label."* Tangible,
   multi-channel (SNS/Pinpoint from the flow or a tool Lambda).
6. **Order cancellation tool.** 🟡 A `cancel_order` flow-module tool (Lambda) to cancel while an order
   is still `processing`/`shipped`. Same pattern as `process_refund` (flat response + spoken `message`,
   idempotent, eligibility by status).
7. **Empathy / de-escalation via sentiment.** 🟡 Use Contact Lens **sentiment** (now that Contact Lens
   is wired — RUNBOOK §8) to detect frustration → soften tone and proactively offer a human / goodwill
   gesture.

### P3 — strategic / heavier (depth + production-readiness)
8. **Voice authentication before sensitive actions.** 🔴 Connect **Voice ID** (voiceprint) or KBA
   (last 4 / DOB) before a refund — the gate to real production transactions.
9. **More self-service actions.** 🟡 Address change, reschedule / track delivery (live carrier status)
   — each is the proven flow-module-tool pattern.
10. **Omnichannel — same agent on web chat / WhatsApp.** 🟡 "Build the brain once, deploy on every
    channel." Reuse the same orchestration agent + tools on chat.
11. **Multi-document knowledge base.** 🟡 Add shipping / warranty policy docs and segment retrieval with
    **multiple Retrieve tools** so the agent picks the right source per question (AWS multi-KB guide).

### Parking lot (lowest — not needed for this demo)
- **Speak any language (multilingual).** Caller switches to Spanish mid-call, agent follows (Nova Sonic
  es-US / en-GB / en-AU voices). Deprioritized — not relevant for this audience/demo; revisit only if a
  multilingual requirement appears.

### Recommended 5-minute exec demo arc
Personalized greeting with order status (#1) → tricky policy question answered only from the KB, with
guardrails refusing a made-up one (#3) → process a refund → "I've texted your confirmation" (#5) →
out-of-scope question → seamless warm handoff *with summary* to a human (#2) → close on the live
deflection dashboard (#4). Hits *personal, trustworthy, capable, seamless, measurable* in one call.
