# Amazon Connect + Nova Sonic — agentic self-service AI agent

An inbound voice line where an **Amazon Nova Sonic** speech-to-speech AI agent ("Amplifier") greets
the caller, **looks up an order** (by order ID, phone number, or the **caller's own number**),
**processes a refund**, **answers return/refund policy questions** from a knowledge base, and
**escalates to a live agent** — built on Amazon Connect's next-gen **agentic self-service** (an
Orchestration AI agent calling **MCP tools** plus a **`Retrieve`** knowledge-base tool).

> ✅ **Status:** working end to end over a real phone call — order lookup (by ID, by phone, and by
> caller ID), refunds (with idempotency + eligibility), policy Q&A from a knowledge base, and
> escalation. The full setup and the hard-won gotchas are in **[docs/RUNBOOK.md](docs/RUNBOOK.md)** —
> read it before reproducing.

## Architecture

A **hybrid** build, because the next-gen pieces (Conversational AI bot + Nova Sonic S2S, the
Orchestration AI agent, flow-module MCP tools) have **little/no stable Terraform or CLI coverage**
yet:

- **Terraform** (`terraform/`) provisions everything deterministic: Connect instance, hours,
  escalation queue, DynamoDB orders table + seed data, the two tool Lambdas + IAM, users, and the
  inbound contact-flow skeleton.
- **Console steps** (`docs/RUNBOOK.md`) build the agentic slice — there is no reliable API for most
  of it: enable bot building, the Conversational AI bot + Nova Sonic speech-to-speech, the
  Orchestration AI agent ("Amplifier"), the two Lambdas wrapped as **flow-module MCP tools**, and
  the contact-flow wiring. **This is the real, validated path.**
- `scripts/` (`10`–`40`, `deploy.sh`) are partial helpers from the original plan. `scripts/30`
  creates the Q-in-Connect assistant/domain (still reused), but the bot/agent/tool/flow steps are
  **superseded by the console RUNBOOK**, and the `flows/*.tpl` templates are **stale** (legacy
  escalate-intent model, not the agentic `Tool`-attribute model).

```
terraform/   IaC for all natively-supported infra (incl. s3-kb.tf — the knowledge-base bucket)
flows/       connect-nova-sonic-inbound-ai-agent.json  (exported, canonical flow — source of truth)
             inbound-ai-agent.json.tpl / inbound-skeleton.json.tpl  (STALE legacy templates)
lambdas/     order_lookup (ID / phone / caller-ID), process_refund (Python 3.12) — FLAT responses
             + a spoken `message`
prompts/     agent-instructions.md (persona / orchestration-prompt reference)
scripts/     deploy.sh, 10..40 (partial/legacy), destroy.sh, lib.sh
docs/        RUNBOOK.md (build guide + lessons learned), FUTURE-ENHANCEMENTS.md,
             return-refund-policy.pdf/.txt (knowledge-base source doc)
```

## Prerequisites

- AWS account on **us-west-2**, on the full **Amazon Connect Customer** (next-gen) tier.
- **Bedrock model access**: not required — AWS retired the *Model access* page; serverless models
  auto-enable on first invocation, and Connect manages Nova Sonic access itself (see RUNBOOK §0).
- A **claimable DID** in the region for the live voice test (small recurring + usage cost).
- Tools: `terraform >= 1.5`, `aws` CLI v2, `jq`.

## Build

1. **Provision the infra:**
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars   # set the instance alias (globally unique)
   terraform init && terraform apply
   cd ..
   ```
2. **Build the agentic slice in the console** following **[docs/RUNBOOK.md](docs/RUNBOOK.md)** §0–§6:
   enable bot building → Conversational AI bot + Nova Sonic S2S → wrap the Lambdas as flow-module
   MCP tools → Orchestration AI agent + security profile → Connect AI agents intent on the bot →
   wire the flow. The RUNBOOK documents every non-obvious step (the ones that cost real time, e.g.
   flow-module **versions**, mapping the Lambda response from **`$.External`**, and re-pointing the
   agent tool to the new module version).
3. **(Optional) Policy Q&A** — RUNBOOK **§7**: create a knowledge base on the domain from the
   Terraform-provisioned S3 bucket, re-add the `Retrieve` tool, grant *Connect assistant – View
   Access*, and instruct the agent. (Caller-ID lookup needs no extra setup — it's in the
   `order_lookup` Lambda; just keep the caller-ID clause in the tool's Instructions.)
4. **Claim a phone number** and set the inbound flow `connect-nova-sonic-inbound-ai-agent` on it.

## Test

**Seed orders** (`terraform/variables.tf`): `ORD-1001/1002/1003` (Jordan Lee / Sam Rivera) plus
`ORD-2001…2004` on phone `+12146817675`. Call the DID and try:

1. *"What's the status of order ORD-1001?"* → reads the status.
2. *"How many orders for my phone, 214 681 7675?"* → lists the caller's orders.
3. *"Look up my orders."* → agent asks *"use the number you're calling from, or a different one?"* →
   on "use mine" it looks up by your **caller ID** (`+12146817675` → `ORD-2001…2004`).
4. *"I'd like a refund for ORD-2003."* → confirms, processes it (sets `status=refunded`,
   `refundable=false`); *"Refund ORD-2002"* → "not eligible"; repeat → "already refunded".
5. *"What's your return window?"* / *"Are opened items refundable?"* → answers from the **knowledge
   base** (return window 30 days, opened items refundable if undamaged, etc.).
6. *"Can I talk to a person?"* → transfers to the escalation queue.

Quick Lambda checks without calling:
```bash
aws lambda invoke --region us-west-2 --function-name connect-nova-sonic-order_lookup \
  --payload '{"order_id":"ORD-1001"}' --cli-binary-format raw-in-base64-out /dev/stdout
aws lambda invoke --region us-west-2 --function-name connect-nova-sonic-process_refund \
  --payload '{"order_id":"ORD-2003"}' --cli-binary-format raw-in-base64-out /dev/stdout
```

> `terraform apply` re-seeds the orders table, so any refunds processed during testing reset on the
> next apply.

## Debugging a call

To reconstruct what happened on a call — which tool the agent invoked, with what input, and why it
escalated — see **[docs/RUNBOOK.md §8 "Observability"](docs/RUNBOOK.md)**: a layered guide from Contact
search → AI agent trace/transcript (Contact Lens) → flow logs → the Lambda `EVENT/PARAMS/RESULT` logs,
with a symptom→layer triage table.

## Roadmap

Knowledge-base policy Q&A, caller-ID lookup, and the observability/debugging guide are **done** (see
RUNBOOK §7–§8 and the `order_lookup` Lambda). Remaining ideas — an order-cancellation tool and a
multi-document knowledge base — are in **[docs/FUTURE-ENHANCEMENTS.md](docs/FUTURE-ENHANCEMENTS.md)**.

## Teardown

```bash
./scripts/destroy.sh
```
Best-effort deletes the Q-in-Connect assistant, the knowledge base + its association, and the
instance integration, then `terraform destroy` (which also removes the KB S3 bucket). The
console-created bot, AI agent, flow modules, and any claimed phone number must be removed manually.

## Cost note

A running Connect Customer instance, a claimed number, and Nova Sonic/Bedrock usage all bill while
deployed. Release the number and destroy when done.
