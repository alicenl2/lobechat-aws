# Q3 — AI chat dump

Two AI tools were used for Q3, plus my own manual price verification on the AWS
console:

1. **Claude (claude.ai)** — produced the Q3 framing (usage assumptions, line-item
   structure, the "Bedrock is the top driver" thesis, cost-cutting levers, unit
   economics, pricing approach). This is the same conversation declared for Q2
   (Session A, "Q3 framing") — summarised again below.
2. **My own manual verification** — I opened the AWS pricing pages for `eu-west-1`
   and screenshotted the live list prices (EC2 On-Demand, EC2 data transfer, T3
   CPU credits, and the Bedrock token tables for Anthropic / Qwen / NVIDIA models).
   These captures are committed in `assets/` and are the price source of record.
3. **Claude Code (Anthropic)** — reconciled my screenshots against the draft
   numbers, fetched the `eu-west-1` list prices I had **not** screenshotted (RDS,
   S3, ALB, EBS, c6i/r6i), recomputed the model with the **real** Bedrock price,
   and wrote `a1.md`. Transcript below (Session B).

The Daveo use case, the architecture I am costing (carried over from Q2), the
usage assumptions, the choice of region/model, and the final wording are mine. The
key correction this session: the screenshot showed Claude Haiku 4.5 at **$1.00 /
$5.00 per MTok**, higher than the **$0.80 / $4.00** I had drafted from the Claude
conversation — so I used the verified screenshot price, which raised the 1000-MAU
Bedrock line from ~$960 to **$1,200/mo**.

---

## Session A — Claude (claude.ai), 2026-06-02

(Full transcript is in `../q2/chat-dump.md`, Session A. The Q3-relevant part:)

**Prompt:** "can you please give me guidelines to help me answer Q2 and Q3"
(pasted the full `FINAL-PROJECT.md` spec).

**Response (Q3 framing):** Claude proposed:
- *Assumptions:* 10 msg/user/day, ~1,500 in / 500 out tokens, 1 RAG query per 2
  messages, 5 MB/user/mo uploads, 12-month retention.
- *Line items* for EC2 / EBS / RDS / S3 / **Bedrock** / ALB / CloudWatch / Route 53 /
  Secrets Manager at 10 / 100 / 1000 MAU.
- *Top driver:* **Bedrock** — estimated ~$960/mo at 1000 MAU on Claude Haiku at
  ~$0.80 / $4.00 per MTok (flagged: "verify on the pricing page, it changes often").
- *Cost-cutting levers:* (1) self-host the model on a GPU EC2 (~58% saving in the
  estimate); (2) prompt caching + RAG truncation (~$180/mo input saving).
- *Unit economics:* ~$26.7 → $3.7 → $1.6 per MAU, curve breaking ~50–75 MAU.
- *Pricing:* ~$6–8/user/mo (cost + ~50% margin at 100 MAU).
- "**Cite current AWS pricing pages for your region with access dates.**"

## Session B — Claude Code (Anthropic), 2026-06-02

Used in this repo to turn the screenshots + framing into the final `a1.md`. What it
did:
- **Read all 10 pricing screenshots** and transcribed the `eu-west-1` numbers:
  EC2 `t3.medium` $0.0456 / `t3.xlarge` $0.1824 / `t3.2xlarge` $0.3648 per hour;
  outbound transfer $0.09/GB after 100 GB free; T3 unlimited credits $0.05/vCPU-h;
  **Bedrock Claude Haiku 4.5 (Ireland, Standard) $1.00 in / $5.00 out**, cache-read
  $0.10, 5-min cache-write $1.25.
- **Flagged the price delta** — verified Haiku price ($1.00/$5.00) is higher than the
  drafted estimate ($0.80/$4.00); recomputed the Bedrock line accordingly
  (`450 MTok in × $1 + 150 MTok out × $5 = $1,200/mo` at 1000 MAU).
- **Fetched the `eu-west-1` list prices I had not screenshotted** (vantage.sh +
  web search to confirm): `c6i.2xlarge` ~$0.380/h, `r6i.large` ~$0.142/h,
  `db.t3.medium` Multi-AZ ~$0.162/h, EBS gp3 $0.0928/GB-mo, S3 Standard $0.023/GB-mo,
  ALB $0.0225/h + $0.008/LCU-h — and noted in `a1.md` which lines are
  screenshot-verified vs. read from the page.
- **Reconciled instance types with Q2** (c6i.2xlarge app, r6i.large Qdrant,
  t3.medium Casdoor, db.t3.medium RDS) and chose a demand-scaled architecture
  (single box at 10/100 MAU → full prod fleet at 1000 MAU) matching the Q2
  Dev→Stage→Prod progression.
- **Built the three line-item tables, the Bedrock working, top-3 drivers, both
  cost-cutting levers (re-quantified against the real price), unit-economics curve,
  and the pricing recommendation**, then wrote `a1.md` and copied the screenshots
  into `assets/`.

---

## What I kept / changed / own

- **Kept:** the overall Q3 structure and thesis from Claude (Bedrock dominates;
  self-host vs. caching levers; per-MAU unit economics).
- **Changed:** replaced every estimated price with the **verified `eu-west-1` list
  price** from my screenshots and follow-up lookups; this raised the Bedrock line
  (~$960 → $1,200) and the 1000-MAU total (~$1,637 → ~$1,846), pushed the
  unit-economics knee later (~50–75 → ~500 MAU), and re-quantified both levers
  (self-host −$770/~42%, caching+length −$550/~30%).
- **Own:** the assumptions, the demand-scaled architecture, the region/model choice,
  the decision to use the screenshot price over the AI estimate, the pricing/fair-use-
  cap recommendation, and the final wording. The screenshots in `assets/` are my own
  captures from the live AWS console.
