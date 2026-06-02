# Q2 — AI chat dump

AI assistance was used while producing this answer; it is declared here.

## Tool — Claude Code (Anthropic), deployment + writing session, 2026-06-02

Claude Code was the agent I used to actually deploy the stack on AWS, and in the
same session I used it to help assemble this Q2 answer. Specifically, Claude Code:

- summarized the real deployment we built together (components, ports, AWS
  resources, networking, secrets, the Casdoor `:8443` and local-Ollama choices)
  so I could ground Q2 in the actual system;
- explained the reverse-proxy / TLS concept (Caddy self-hosted vs ALB + ACM
  managed) when I asked what that section meant;
- converted the sections I pasted as plain text into proper markdown tables;
- did light grammar / typo cleanup on my prose (e.g. fixing "maintenant" →
  "maintenance", "Than" → "Then");
- flagged a contradiction in my trade-off section (I had written that production
  "doesn't cost a lot", which conflicted with my own 2/5 cost-efficiency score),
  and I corrected the wording to match my table.

## What is my own work

The architecture decisions are mine: the per-environment mapping and instance
types (`t3.xlarge`, `c6i.2xlarge`, `r6i.large`, `db.t3.medium`), the choice of
which components become AWS managed services in prod (RDS, S3, Bedrock, ALB/ACM,
Secrets Manager, CloudWatch), the Qdrant EBS sizing logic and snapshot/recovery
policy, the promotion flow (branching, CI/CD, ECR tagging), the data strategy
(synthetic dev data, anonymized stage data, prod backup/restore), the trade-off
scores, and the three architecture diagrams (made by me). The synthetic dev CV
dataset described in the Data strategy section was generated with Claude.

## Note

Where I drafted prose with other assistants (ChatGPT / Claude) outside this
session, that assistance is covered by this same declaration; the substantive
engineering choices and the diagrams are my own.
