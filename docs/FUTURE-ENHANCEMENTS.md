# Future enhancements (backlog)

Deferred ideas for the Connect + Nova Sonic agentic self-service POC. Not needed for the core demo
(Nova Sonic voice → orchestrator → order_lookup / process_refund); revisit after that is solid.

## 1. ANI auto-detect for phone lookup
**Goal:** when a caller wants to look up orders by phone and hasn't given a number, ask *"Would you
like to use the number you're calling from?"* — if yes, use the caller's ANI; otherwise ask them to
say a number.

**Why it's deferred:** the orchestrator does **not** see the caller's number (ANI) by default, so it
needs explicit wiring.

**Implementation sketch:**
1. **Flow:** before the *Get customer input* block, add a **Set contact attributes** block that stores
   **System → Customer Number** (`$.CustomerEndpoint.Address`) into an attribute (e.g. `callerNumber`),
   and pass it to the bot as a **session attribute**.
2. **Agent:** instruct Amplifier (tool instructions and/or the orchestration prompt) to offer the
   calling number for phone lookups and, on yes, call `order_lookup` with the caller's number.
3. **Open question to verify:** exactly how a session/contact attribute is surfaced to the
   orchestrator so it can use the value (may require the orchestration prompt, not just tool
   instructions). `order_lookup` already E.164-normalizes the phone, so the value just needs to reach
   the tool.

**Simpler path discovered (2026-06-21):** the caller's ANI is **already in the Lambda event** at
`event["Details"]["ContactData"]["CustomerEndpoint"]["Address"]` (confirmed: `+12146817675`). So
`order_lookup` could simply **fall back to the ANI** when no order_id/phone is supplied — no flow
wiring needed. The only remaining piece for the "ask first" UX is the agent prompting the caller; or
skip the prompt and just look up by ANI automatically as a convenience.

## 2. Knowledge base lookup (policy Q&A)
**Goal:** upload a document (e.g. **return / refund policy**) and let Amplifier answer free-form
questions about it ("what's your return window?", "are opened items refundable?").

**Why it's a natural fit:** this is exactly the built-in **`Retrieve`** tool we removed during setup
(it searches a knowledge base). Re-adding it + a knowledge base lights this up — no new Lambda needed.

**Implementation sketch:**
1. **Create a knowledge base** on the Q-in-Connect **domain** (`connect-nova-sonic-demo-assistant`):
   AWS Console → Amazon Connect → instance → **AI Agents** → **Add integration** → choose a source
   (Amazon S3 with the policy doc, Web crawler, or an existing Bedrock Knowledge Base). Supported
   content: HTML, Word (DOCX), PDF (not encrypted), or UTF-8 text, up to 1 MB.
2. **Upload the policy document** (e.g. `return-refund-policy.pdf`) to that source and let it ingest.
3. **Re-add the `Retrieve` tool** to the Amplifier agent (Add tool → Amazon Connect namespace →
   `Retrieve`) and grant its permission in the agent's security profile (it showed *Insufficient*
   before because no KB/permission existed — *Knowledge Base (Retrieve)* needs *Connect assistant –
   View Access*).
4. **Instruct the agent** to use `Retrieve` for policy / general questions (vs. `order_lookup` /
   `process_refund` for order actions).
5. Publish + test by asking a policy question over the call.

**Note:** the orchestration agent type supports bring-your-own **Bedrock Knowledge Base** integration,
which is the cleanest path if a Bedrock KB already exists.
