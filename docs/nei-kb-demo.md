# NEI knowledge-base demo (temporary / experimental)

> **Branch `nei-kb-demo` — do NOT merge to `main`.** A throwaway test of "use a public
> website as an isolated knowledge base," fully separated from the core Amplify demo so it can
> be torn down with zero impact. Built 2026-06-25.

## What this demonstrates
Pull a website's content (https://www.neirelo.com — NEI Global Relocation, a corporate relocation
company) into a **second, isolated Q-in-Connect knowledge base**, surfaced through a **second
`Retrieve` tool** on the existing Amplifier agent — without touching the existing return/refund
policy KB or order tools.

## Architecture (all isolated from the core demo)
| Piece | This demo | Core demo (untouched) |
|---|---|---|
| S3 bucket | `…-nei-kb-<acct>` (`terraform/nei-kb.tf`) | `…-kb-<acct>` (`terraform/s3-kb.tf`) |
| KB integration | **`nei-kb`** | policy KB |
| Retrieve tool | **`nei_retrieve`** | `Retrieve` |
| Content | `docs/nei-services.txt` (crawled site) | `docs/return-refund-policy.pdf` |

Each Retrieve tool binds to **one** Assistant Association, so the two KBs are physically isolated —
neither tool can read the other's content. The tool **instructions** handle routing (which tool the
agent picks per question).

## Content: `docs/nei-services.txt`
- A 40-page crawl of neirelo.com (services, about, global-services, digital-solutions, ~20 articles,
  podcasts, contact) — ~446 KB plain text, under the 1 MB/file KB limit.
- Repeated nav/cookie/footer boilerplate stripped; a curated **KEY FACTS** block prepended so common
  factual questions (HQ, founded, contact, services) hit a high-signal chunk.
- Regenerate: a same-domain crawler + cleanup (see git history of this file). After editing the doc,
  `terraform apply` re-uploads it; then **re-sync** the `nei-kb` integration.

## Setup (recap)
1. `terraform -chdir=terraform apply` → creates the isolated bucket + uploads the doc;
   `terraform -chdir=terraform output nei_kb_s3_uri`.
2. Console → **AI Agents → Add integration → Amazon S3** → the NEI bucket URI → name it `nei-kb` →
   **Sync** → wait for `nei-services.txt` to index.
3. Console → **Amplifier → Add tools → Add existing AI Tool → Amazon Connect → Retrieve** → name
   `nei_retrieve` → **Assistant Association = the NEI KB** → set instructions (below) → **Publish**.
   (No new permission — *Connect assistant – View* already granted.)

### `nei_retrieve` instructions (grounded + brief)
> Use this tool for questions about NEI Global Relocation and the relocation/mobility services NEI
> provides. For Amplify order, refund, or return-policy questions, use the other tools instead.
>
> Keep every answer very brief — one or two short sentences, conversational for voice. Answer only the
> exact question asked. Do NOT volunteer company history, founding dates, locations, awards, or any
> background the caller didn't ask for. If they want more, ask "Would you like more detail?" instead of
> giving it unprompted.
>
> Answer ONLY from the content this tool returns. If it isn't there, say you don't have that
> information — never guess, assume, or invent names, prices, dates, or policies.

(Also scope the **original `Retrieve`** tool: "Use ONLY for Amplify return/refund policy questions;
do not use for NEI/relocation questions.")

## Test cases
| # | Ask | Expected | Checks |
|---|---|---|---|
| 1 | "Tell me about NEI's relocation services." | 1–2 sentence services summary; **not** company history | brevity + on-topic |
| 2 | "Does NEI help with visa and immigration?" | Short "yes" | retrieval + brevity |
| 3 | "How much does NEI charge for a relocation?" | "I don't have pricing details" — **no invented price** | anti-hallucination |
| 4 | "Where is NEI headquartered?" | "Omaha, Nebraska" (one sentence) | factual retrieval (KEY FACTS) |
| 5 | "When was NEI founded?" | "1985" | factual retrieval |
| 6 | "Does NEI have an office in Tokyo?" | No — only Omaha / Switzerland / Singapore; **doesn't invent one** | anti-hallucination |
| 7 | "Who is NEI's CEO?" | "I don't have that information" — **no made-up name** | anti-hallucination |
| 8 | "What's your return window?" | "30 days" from the **policy** KB (not NEI) | routing / isolation |
| 9 | "What's the status of order ORD-1001?" | Order tool still answers | no regression |
| 10 | "I'd like to speak to a person." | Escalates | no regression |

Pass = 1/2/4/5 are short & correct, 3/6/7 refuse to fabricate, 8/9/10 confirm the core demo is
unaffected.

## Teardown (clean, zero impact on the core demo)
1. **Console:** remove `nei_retrieve` from Amplifier → Publish; delete the `nei-kb` integration.
2. **Terraform:** delete `terraform/nei-kb.tf` → `terraform apply` (force_destroy empties + removes the
   bucket). Or `terraform destroy -target=…` per the header comment in that file.
3. Optionally delete `docs/nei-services.txt`, `docs/nei-kb-demo.md`, and the `nei-kb-demo` branch.
