# Console runbook — the non-IaC slice

Terraform creates the instance, queue, DID, DynamoDB + sample data, Lambdas, and the contact flow
skeleton. These steps cover the brand-new pieces that don't have stable Terraform/CLI coverage
yet. The wiring scripts (`scripts/10`..`40`) automate what they can and point back here.

Region: **us-west-2**. Connect admin site URL:
`https://<instance_alias>.my.connect.aws/` (from `terraform output connect_instance_alias`).

---

## 0. One-time prerequisites

- **Bedrock model access**: no longer a manual step. AWS **retired the Bedrock *Model access*
  page** — serverless foundation models now auto-enable across all commercial regions on first
  invocation. Connect also manages its own Nova Sonic access. Nothing to request here.
- **Connect Customer (next-gen) tier**: the instance must be on the full **Connect Customer**
  (next-gen) tier. Confirm in AWS Management Console → Amazon Connect → **Customer** page → the
  "Confirm Amazon Connect Customer" card should show ✓ (a *Change* button, not *Enable*). Our
  `connect-nova-sonic-demo` instance is already on it (`list-instance-attributes` → `MAX_PACKAGE=true`).
- **Enable bot building** (this is what makes the **Bots** option appear): AWS Management Console →
  Amazon Connect → select `connect-nova-sonic-demo` → nav **Flows** → check **Enable Lex Bot
  Management** *and* **Enable Bot Analytics and Transcripts** → **Save**. Creates a Lex
  service-linked role. Without this, the admin-site Flows page has no Bots option.
  (Maps to instance attributes `BOT_MANAGEMENT` / `ENABLE_BOT_ANALYTICS_AND_TRANSCRIPTS`.)
- **Security profile perms** for the user creating bots: *Channels and Flows → Bots →*
  View/Edit/Create, and *Analytics and Optimization → Historical metrics → Access*.

## 1. Create the Conversational AI bot  (script 10)

> "Bots" is **not** a left-nav item — it's on the **Flows page**.

1. Connect admin site → **Routing → Flows**, then on the Flows page choose **Bots → Create bot**.
   - Name: `<instance_alias>-self-service`.
2. Add a **locale**: English (US) / `en-US`.
3. Add a **custom** intent with ≥1 utterance (e.g. `WelcomeIntent` / utterance `Hello`) so the locale
   can build — the auto-created fallback alone won't build (see Lessons). **Build language.**
4. No ARN to copy in the agentic build — the flow's *Get customer input* block (§6) selects the bot
   from a dropdown (`connect-nova-sonic-demo-self-service`, alias **TestBotAlias** / `TSTALIASID`).
   The bot's own ARN is a Lex ARN, e.g.
   `arn:aws:lex:us-west-2:<acct>:bot-alias/<botId>/<aliasId>` — only needed if referencing it directly.

## 2. Enable Nova Sonic Speech-to-Speech  (script 20)

Nova Sonic is a per-locale **Speech model** setting on the Conversational AI bot (not a separate bot
type). On the bot's **Configuration** tab, en-US locale:

1. **Speech model** → **Edit**.
2. **Model type**: *Speech-to-Speech*.
3. **Voice provider**: *Amazon Nova Sonic* → **Confirm**.
4. If "Unbuilt changes" shows → **Build language**; wait until Active.

The flow's *Set voice* block is already configured to a Nova Sonic-compatible expressive voice
(**Matthew**, **Generative**, en-US). Other launch voices: Amy (en-GB), Olivia (en-AU), Lupe (es-US).

> **Architecture note (agentic, not legacy).** Amazon Connect has two self-service models. *Legacy*
> self-service uses a Q-in-Connect answer-generation prompt + Lambdas registered as actions (this is
> what `scripts/30`'s CLI attempted — its `create-ai-prompt` call fails on undocumented
> type/`apiFormat` mappings). This POC uses **agentic self-service**: an **Orchestration** AI agent
> that reasons across steps and calls **MCP tools**. The tools are the existing Lambdas wrapped as
> **flow-module tools** — no MCP server / AgentCore Gateway needed. Sections 3–6 below replace the
> old legacy steps. `scripts/30` is superseded except for the Q-in-Connect assistant/domain it
> creates (which agentic reuses); `scripts/40` (flow wiring) is being reworked for the `Tool`
> session-attribute routing described in §6.

## 3. Wrap each Lambda as a flow-module MCP tool  ✅ verified

Do this once per Lambda (`order_lookup`, then `process_refund`). The Lambdas are already associated
with the instance, so they appear in the Lambda picker.

1. Admin site → **Routing → Flows → Modules** tab → create a module **as a tool**. Name it
   e.g. `order_lookup_module` / `process_refund_module`. Give it a **description** — it's
   **mandatory** for the module to be usable as an AI-agent tool (and the description is what the
   agent reads to decide when to call the tool, e.g. "This tool retrieves an existing order").
2. **Settings** tab (Designer or JSON-schema mode):
   - **Input** schema properties: `order_lookup` → `order_id` (String), `customer_phone` (String);
     `process_refund` → `order_id` (String).
   - **Output** schema: define **flat, named String properties matching the Lambda's response keys**
     — `order_lookup` → `found`, `message` (+ optionally `count`, `status`, `item`, `amount`,
     `customer_name`, `refundable`, `order_id`); `process_refund` → `success`, `message`. ⚠️ Only
     declare fields the Lambda returns on **every** code path, OR have the Lambda always return all
     keys (empty string when N/A) — otherwise the Exit-module mapping for a missing field errors
     ("I am having trouble accessing…"). The always-present pair is `found`/`success` + `message`;
     `message` is a ready-to-speak summary, so found+message alone is enough.
3. **Designer**: **Entry → Invoke AWS Lambda function** block → select the Lambda.
   - Function input parameters → for each, **Set dynamically** → Namespace **Modules**, Key
     **Input**, Parameter = `order_id` (and `customer_phone`). This passes the agent's args through.
   - **Response validation: JSON**.
4. Add **one Return ("Exit module")** block; connect **both** the Lambda's **Success** and **Error**
   outputs to it. **Map the output from the `External` namespace** — that's where a flow module
   exposes the Lambda's response (confirmed in flow logs: `ContactFlowModuleType:
   InvokeExternalResource` → `ExternalResults: {…}`). Use **Set manually → Form**, which lists each
   output schema property with a JSONPath box; set each to **`$.External.<key>`** (e.g.
   `message` → `$.External.message`, `found` → `$.External.found`). ❌ **Do NOT use `Modules →
   Result`** — despite the namespace label, it does **not** contain the Lambda response, so the
   module returns empty and the agent says "I don't see any orders." (The "Set dynamically" path
   only maps one field; "Set manually → Form" maps each field.)
5. **Save → Publish**, **then create a VERSION** of the module. ⚠️ **Critical, non-obvious:** a
   plain Save/Publish does **not** register the module into the AI-agent tool catalog. You must
   **create a published version** (Module → Versions → create version). Until a version exists, the
   module will **not** appear under the **Flow Modules** namespace in the agent's "Add existing AI
   Tool" picker, and the security profile's **Flow modules** permission section shows "No Flow
   modules available". (This is not propagation, permissions, or login type — it's the missing
   version.)
6. ⚠️⚠️ **After EVERY module version change, re-point the agent's tool to the new version.** AI-agent
   tools **pin a specific module version** — they do **not** auto-follow the latest. If you edit the
   module + cut a new version but leave the tool on the old one, the tool keeps invoking the **old**
   output mapping and your fix silently has no effect (the Lambda still runs, so it *looks* wired).
   Update the tool's version in **Amplifier → Tools → <tool> → Edit** (or Remove + re-add picking the
   newest version), then **Publish** the agent. *This was the multi-hour root cause of "tool returns
   data but the agent ignores it."*

## 4. Create the Orchestration AI agent  ✅ verified

> **Do this first (prerequisite):** create the security profile that grants tool access *before*
> adding tools — flow-module tools won't appear / will show *Insufficient* otherwise. Users →
> Security profiles → create `amplifier-agent-tools` with **Channels and Flows → Flow Modules →
> All Access** + **AI agent designer → AI Agents → All Access**, and tick the **per-module Access**
> for each module in the **Flow modules** section. Assign it to the agent (step 6) and log in as a
> real Connect user (not emergency access). See the *Permissions* lessons.

Admin site → **AI agent designer → AI agents → Create AI agent**:

1. Type **Orchestration**; **Copy from existing → `SelfServiceOrchestratorVoice`** (the **Voice**
   variant — for a phone/Nova Sonic experience; there's also `SelfServiceOrchestratorChat`). Gives
   default `Complete` + `Escalate` Return-to-Control tools (plus a `Retrieve` knowledge-base tool —
   removed here, then re-added in §7 once the knowledge base exists) and the orchestration prompt.
2. Name it `Amplifier` (the project `agent_name`).
3. **Add tools** → **Add existing AI Tool** → Namespace **Flow Modules** → add the two flow-module
   tools from §3 (they only appear here once each module has a published **version** — see §3 step
   5). Keep the default `Complete` / `Escalate`; remove `Retrieve` for now (no KB yet — it's re-added
   in **§7** for policy Q&A once the knowledge base is created).
   Also grant each module **Access** in the security profile's **Flow modules** section (Users →
   Security profiles → your profile → Flow modules) so the agent's tool permission shows
   *Sufficient*, not *Insufficient*. Note: emergency-access (console) login is profile-less and
   won't surface these tools — log in as a real Connect user (e.g. `demo.admin`) whose profile has
   Flow Modules access.
4. Prompt: start from the default `SelfServiceOrchestration` (optionally fold in the persona from
   `prompts/agent-instructions.md`). Orchestrator responses must be wrapped in `<message>` tags —
   the default handles this.
5. **Publish.**
6. **Security profile**: Users → Security profiles → create one granting the tools the agent needs;
   select it in the agent's **Security Profiles** section.
7. **Set as default**: AI Agents page → **Default AI Agent Configurations** → **Self Service** row →
   select `Amplifier`.

## 5. Enable the Connect AI agents intent on the bot  ✅ verified

On the Conversational AI bot (`connect-nova-sonic-demo-self-service`), enable the **Connect AI agents
intent**. This is what routes the bot conversation into the orchestrator agent.

## 6. Wire and publish the flow  ✅ verified (built in console)

> **Canonical definition:** `flows/connect-nova-sonic-inbound-ai-agent.json` is the exported, working
> flow — use it as the source of truth. The old `flows/inbound-ai-agent.json.tpl` + `scripts/40` are
> **stale** (they branch on a legacy `escalate` intent, not the `Tool` session attribute) and should
> be reworked (parameterize the export) or deleted. Note the export includes an auto-added
> **`CreateWisdomSession`** block (binds the Q-in-Connect domain to the contact — required for the AI
> agent to run).

Edit the Terraform-created inbound flow **`connect-nova-sonic-inbound-ai-agent`** (Routing → Flows).
It starts as a skeleton (Entry → Set logging → Play prompt → Disconnect); build it into:

```
Entry → Set logging behavior (Enabled)
      → Set voice (Matthew / Generative / en-US)
      → Play prompt: "Thanks for calling Amplify Total Experience."
      → Get customer input  (Lex bot: connect-nova-sonic-demo-self-service, alias TestBotAlias)
            • Default → Check contact attributes (Lex / Session attributes / key = Tool)
                  - Equals "Complete" → Play prompt "Thanks for calling. Goodbye." → Disconnect
                  - Equals "Escalate" → Set working queue (…-escalation) → Transfer to queue → Disconnect
                  - No Match → Disconnect
            • Error → Play prompt "Sorry, a technical issue…" → Disconnect
```

Block-by-block notes (the console specifics that aren't obvious):
- **Set voice** → tick **Override speaking style** → it reveals radios **Standard (Legacy) /
  Neural speaking style / Generative** — choose **Generative**. (It never says "Nova Sonic"; the
  S2S model is configured on the *bot* in §2. Matthew + Generative = the Nova Sonic-compatible voice.)
- **Get customer input** → **Select a Lex bot** → `connect-nova-sonic-demo-self-service`, alias
  **TestBotAlias** (= `TSTALIASID`; the "should not be used for production traffic" note is fine for
  the POC). Its only outputs are **Default** and **Error** (not per-intent) — the orchestrator runs
  inside the bot and exits via Default when it picks a Return-to-Control tool.
- The block's **required "Customer prompt or bot initialization"** field = the spoken greeting, e.g.
  *"I'm Amplifier, your virtual assistant. How can I help you today?"* Keep it open-ended (no IVR
  menu) — the orchestrator handles free-form requests. Avoid double-greeting with the welcome prompt.
- **Routing** is on the Lex **Session attribute `Tool`** (capital T) = the Return-to-Control tool the
  agent picked (`Complete` / `Escalate`), not on intents.
- **Every output must be connected** or Publish fails (Set working queue Error → Disconnect;
  Transfer to queue at-capacity/error → Disconnect; No Match → Disconnect).

**Save → Publish.** Escalation only reaches a human if an agent is staffed in the
`…-escalation` queue's routing profile — fine to leave unstaffed for a self-service POC test.

Then associate the flow with a phone number under **Channels → Phone numbers** (the Terraform DID
claim is commented out — claim manually; small recurring + usage cost). To validate *without* a
number first, use the **bot Test panel** (text) to exercise the agent + tools for free.

## 7. Knowledge base — policy Q&A from S3  (enhancement)

Lets Amplifier answer free-form **return / refund policy** questions ("what's your return window?",
"are opened items refundable?", "is there a restocking fee?") using the built-in **`Retrieve`** tool
against a knowledge base — no new Lambda. The policy document and its S3 source are managed by
Terraform; the knowledge base + tool wiring is console.

**Terraform provides (already applied):**
- `docs/return-refund-policy.pdf` — the generic policy document (regenerate from
  `docs/return-refund-policy.txt` with `cupsfilter return-refund-policy.txt > return-refund-policy.pdf`).
- An S3 bucket + the uploaded PDF (`terraform/s3-kb.tf`). Get the source location:
  `terraform -chdir=terraform output kb_s3_uri`
  → `s3://connect-nova-sonic-demo-kb-<account-id>/policies/return-refund-policy.pdf`.
  (SSE-S3, not the CMK — see the note in `s3-kb.tf`.)

**Console steps:**
1. **Create the knowledge base on the existing Q-in-Connect domain.** This is in the **AWS Management
   Console**, *not* the `.my.connect.aws` admin website. The KB is created as an **integration on the
   domain** (`connect-nova-sonic-demo-assistant` — the assistant the agent already uses; see
   *Terminology*). The domain already exists, so skip "Add domain" and go straight to **Add integration**:
   - AWS console → **Amazon Connect** → click your instance (`connect-nova-sonic-demo`).
   - Left nav → **AI Agents** → **Add integration** → **Create a new integration**.
   - **Source** → **Amazon Simple Storage Service (S3)**.
   - Under **Connection with S3**, paste the **bucket** URI (not a single-object key) — e.g.
     `s3://connect-nova-sonic-demo-kb-<account-id>` (or `.../policies/` to scope to the prefix) — or
     **Browse S3** and pick the bucket. The integration ingests the supported files it finds under
     there. (`terraform output kb_s3_uri` points at the exact object — handy for `aws s3 ls`
     verification, but give the integration the bucket/prefix, not that full object URI.)
   - **Encryption** → default (AWS owned key) is fine for the POC → **Next** → review → **Add integration**.
   - Supported content: HTML, DOCX, PDF (not encrypted/password-protected, no embedded scripts), or
     UTF-8 text, ≤ 1 MB — our generated PDF qualifies.
   - **Bucket access is already handled:** `terraform/s3-kb.tf` attaches a bucket policy granting the
     `app-integrations.amazonaws.com` principal `s3:GetObject` / `GetBucketLocation` / `ListBucket`
     (Q in Connect ingests S3 via AWS AppIntegrations). SSE-S3 (not the CMK) keeps it readable without
     a KMS grant. If you ever switch the bucket to a CMK, also grant that principal `kms:Decrypt`.
2. **Sync / ingest** the source and wait until the document shows **indexed** (a minute or two for one
   small PDF). Until it's indexed, `Retrieve` returns nothing and the agent will say it can't find a
   policy.
3. **Re-add the `Retrieve` tool to Amplifier** (it was removed in §4). AI agent designer → **Amplifier**
   → **Add tools → Add existing AI Tool → Namespace `Amazon Connect` → `Retrieve`**. The tool config
   has a **required `Assistant Association`** field — "Select a knowledge base association to configure
   the retrieval source." Pick the single association shown; its sub-line **`Connect Knowledge Base ID:
   <id>`** confirms it points at the policy KB you made in step 1. (If that dropdown is *empty*, the KB
   isn't associated/ready yet — go back to step 1/2.)
4. **Grant the permission** so `Retrieve` shows *Sufficient*, not *Insufficient*: the Knowledge Base
   `Retrieve` tool needs **Connect assistant – View Access**. Users → Security profiles →
   `amplifier-agent-tools` → enable **Contact Control Panel / Amazon Q (Connect assistant) → View**
   (the *Connect assistant – View Access* permission) → Save. (This is the exact permission that made
   `Retrieve` show *Insufficient* during initial setup, when no KB existed.)
5. **Instruct the agent** (the `Retrieve` tool's **Instructions** field) to use it for **policy and
   general questions** — return windows, refund eligibility rules, shipping/restocking fees,
   non-returnable items — and to keep using `order_lookup` / `process_refund` for actions on a
   specific order. e.g. *"Use Retrieve to answer questions about return and refund policy. Quote the
   policy; do not invent terms. For looking up or refunding a specific order, use the order tools."*
6. **Publish** the agent. (Unlike flow-module tools, `Retrieve` is a built-in tool and does **not**
   pin a module version — no re-point needed; just Publish.) Confirm **Self Service** default still
   points at Amplifier / Latest (§4.7).
7. **Test** — bot **Test panel** (text, free) first, then a live call: ask *"What is your return
   window?"* (→ 30 days), *"Are opened items refundable?"* (→ yes within 30 days if undamaged/complete),
   *"Is there a restocking fee?"* (→ up to 15% on opened large electronics / no original packaging).
   The orchestrator should call `Retrieve` and answer from the document, and still handle
   order/refund requests via the existing tools.

**Updating the document later:** edit `docs/return-refund-policy.txt` → regenerate the PDF → `terraform
apply` (uploads a new object version) → **re-sync** the knowledge base in the console so it re-ingests.

## Escalation semantics

The orchestrator's default **Escalate** Return-to-Control tool ends the AI conversation and stores
`Tool=Escalate` (plus any input params, e.g. an escalation summary) as Lex session attributes. The
flow's **Check contact attributes** block (§6) reads `Tool` and transfers to the escalation queue
created by Terraform (`<project>-escalation`). You can replace the default Escalate tool with a
custom one whose input schema captures `escalationReason` / `escalationSummary` / `sentiment` for an
agent screen-pop.

## Lessons learned / gotchas (hard-won)

Consolidated quick-reference. Most of these cost real time to discover; the platform is new (GA Nov
2025) and the console/API terminology drifts.

**Tier & enablement**
- The instance is on the full **Connect Customer** tier (console *Customer* page shows ✓ + a
  *Change* button; `list-instance-attributes` → `MAX_PACKAGE=true`). "Basic" was a wrong early guess.
- **Bot building must be enabled** before any bot work: Console → instance → **Flows** → *Enable Lex
  Bot Management* + *Enable Bot Analytics and Transcripts*. Maps to `BOT_MANAGEMENT` /
  `ENABLE_BOT_ANALYTICS_AND_TRANSCRIPTS`. **Not settable via CLI/Terraform** (`update-instance-attribute`
  enum excludes them) — console only.
- After enabling anything permission/feature-related, **log out and back in** — this admin site
  caches the session and silently won't show new features/permissions until you do. (Bit us
  repeatedly: bot-building, security profiles, tool permissions.)

**Bot & Nova Sonic**
- "Bots" is now the **Conversational AI** tab on the **Flows** page (not a left-nav item).
- Nova Sonic is a per-locale **Speech model → Speech-to-Speech → Amazon Nova Sonic** on the bot —
  **not** a separate bot type. Selecting it requires **another Build language** to go Active.
- A locale needs a **custom intent with ≥1 utterance** to build; built-in intents (incl. the
  fallback) **can't** have utterances. Minimal working fix: a `WelcomeIntent` with utterance `Hello`.
- `bedrock list-foundation-models` does **not** list `nova-sonic` in us-west-2, yet S2S works —
  Connect manages Nova Sonic access itself, so that check is **not** a gate. (Also moot now: AWS
  retired the *Model access* page; serverless models auto-enable on first invocation.)

**Terminology**
- **One resource, three names** — watch for this everywhere: the API/CLI calls it a `qconnect`
  **assistant**, the ARN service namespace is **`wisdom`** (`arn:aws:wisdom:...:assistant/<id>`), the
  AI agent designer page calls it a **"Domain"**, and the *Enable Connect AI agent intent* dialog on
  the bot labels the very same value **"Assistant ARN"**. Ours:
  `connect-nova-sonic-demo-assistant` = Domain ID `b1e3dc48-d09d-4954-a7a1-4c1473d31153` =
  `arn:aws:wisdom:us-west-2:123456789012:assistant/b1e3dc48-d09d-4954-a7a1-4c1473d31153`.
- This POC is **agentic** self-service (Orchestration agent + MCP tools), not the legacy
  answer-generation-prompt model that `scripts/30` attempted.

**Flow-module MCP tools (the big time sink)**
- Read the agent's **inputs** via the **`Modules`** namespace (Key **Input**) in the Invoke-Lambda
  block. Read the **Lambda's response** in the **Exit module** via the **`External`** namespace
  (`$.External.<key>`) using **Set manually → Form** — NOT `Modules → Result` (which is empty for a
  Lambda response, despite the misleading name). Flow logs confirm the Lambda result lands in
  `ExternalResults`.
- **AI-agent tools PIN a module version and do not auto-follow latest.** After every module edit +
  new version, re-point the tool to the new version and re-Publish the agent — otherwise the tool
  invokes the stale version's output mapping and your change has no effect (the Lambda still runs, so
  it deceptively looks correct). This was the single biggest time sink.
- Keep Lambda responses **flat** (top-level String key/values) + a ready-to-speak **`message`**; the
  agent can be told (tool Instructions) to read `message`. Only map output fields the Lambda returns
  on every path (or always return all keys with "" defaults).
- Set the Lambda block's **Response validation = JSON** (our Lambdas return nested/boolean fields;
  STRING MAP only handles flat all-string objects).
- The module **Output schema must have ≥1 property** (flat named String fields, e.g. `found`,
  `message`). An empty output schema → the Return/"Exit module" block has nothing to return →
  **publish fails** with a generic "Failed to publish module".
- Both Lambda **Success and Error** branches can go to **one** Return ("Exit module") block. In it,
  use **Set manually → Form** and map each output property to **`$.External.<key>`** (the Lambda
  response lives in `External`). ❌ Do **not** use `Modules → Result` — it's empty for a Lambda
  response, so the module returns nothing and the agent says "I don't see any orders."
- **A flow-module tool needs a published VERSION**, not just Save/Publish. Until a version exists it
  does NOT appear under the **Flow Modules** namespace in the agent tool picker and shows "No Flow
  modules available" in the security profile. **This was the multi-hour blocker.** (Module console →
  Publish **and** Create version.)
- A flow-module **description is mandatory** for it to be usable as an AI-agent tool (it's also what
  the agent reads to decide when to call it).

**Flow wiring**
- **Set voice**: the **Generative** engine is hidden behind the **Override speaking style** checkbox
  (Standard/Neural/**Generative** radios). Nothing in this block says "Nova Sonic" — Matthew +
  Generative is the compatible combo; S2S itself is on the bot (§2).
- **Get customer input** with the bot has only **Default** / **Error** outputs (orchestrator exits
  via Default). Route the agent's decision off the Lex **Session attribute `Tool`** (`Complete` /
  `Escalate`) with a **Check contact attributes** block — not off intents.
- Its **"Customer prompt or bot initialization"** field is **required** — that's the spoken greeting.

**Permissions / security profiles**
- Tool access is governed by **security profiles**: enable **Channels and Flows → Flow Modules →
  All Access** + **AI agent designer → AI Agents → All Access**, AND — separately — tick the
  **per-module Access checkbox** for each module in the profile's **Flow modules** section. The
  broad "Flow Modules - All Access" alone does **not** make a tool *Sufficient*; the per-module
  Access grant in the profile *assigned to the agent* (`amplifier-agent-tools`) is what flips
  Insufficient → Sufficient.
- **Emergency access (console link) is profile-less** and will NOT surface flow-module tools — log in
  to the admin site as a real Connect user (e.g. `demo.admin`) whose security profile grants them.
- For the agent's tools to show **Sufficient** (and to actually fire), the relevant security
  profile(s) must grant the tool — and for agent-assist/testing, the **human** user's profile must
  match the AI agent's.
