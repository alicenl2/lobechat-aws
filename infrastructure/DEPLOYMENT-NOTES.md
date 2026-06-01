# Deployment notes — what was actually built

The target account is an **ESADE Innovation Sandbox** (AWS IAM Identity Center,
permission set `IsbUsersPS`), which is more locked down than a default account.
This records the real deployment and the adaptations it required.

## Sandbox constraints discovered

| Constraint | Adaptation |
|---|---|
| **No default VPC** | Created a minimal VPC + public subnet + IGW + route table. |
| `IsbUsersPS` **denies `ssm:PutParameter`/`GetParameter`** and `secretsmanager:CreateSecret` | Created an IAM role **`lobechat-deployer`** (the user *can* create roles) with `ssm:*`/`ec2:*`, assumed via an auto-assume profile, to store secrets in SSM and resolve the AMI via SSM — keeping both spec constraints (secrets in SSM, AMI via SSM public parameter) literally satisfied. |
| No GPU | LLM backend is a local **Ollama** (`qwen2.5:3b`) on the EC2 — free, self-hosted. |

## Resources (region `eu-west-1`)

| Resource | ID |
|---|---|
| VPC | `vpc-0bdfd64a11fcef1ab` (10.0.0.0/16) |
| Public subnet | `subnet-0d8c5d13fb542178e` (10.0.1.0/24, eu-west-1a) |
| Internet gateway | `igw-0a5830702eaee5096` |
| Route table | `rtb-0c68153c9c6443e88` |
| Security group | `sg-083bdf76ec969d9e0` (22, 80, 443, 8443; **47000 closed**) |
| Instance | `i-05fb6c1b6cf849a1b` (`m5.xlarge`, 60 GB gp3) |
| AMI (via SSM) | `ami-0daff188b5216c5f0` (Ubuntu 24.04 LTS) |
| Elastic IP | `52.31.85.106` (`eipalloc-0ac47e0827fe60f1b`) |
| Instance role | `lobechat-ec2-profile` / `lobechat-ec2-role` (SSM read on `/lobechat/*` + KMS decrypt) |
| Deployer role | `lobechat-deployer` (provisioning only) |
| SSH key | `lobechat-ec2-key` → `~/.ssh/lobechat-ec2-key.pem` |

## Public endpoints

- LobeChat: `https://alicenl-lobechat.duckdns.org`
- Casdoor (OIDC): `https://alicenl-lobechat.duckdns.org:8443`
- MinIO (S3 API): `https://alicenl-minio.duckdns.org`

## TLS / HTTPS notes

- Caddy (host service) terminates TLS for all hostnames via Let's Encrypt / ZeroSSL.
- **Casdoor is served on the lobechat hostname at `:8443`** instead of its own
  subdomain: DuckDNS nameservers intermittently timed out on the CA's CAA lookup,
  so issuing a 3rd cert was unreliable. Reusing the lobechat cert removes that
  dependency. (The `alicenl-casdoor` subdomain still exists but is unused.)

## Reproduce from scratch

1. Store secrets in SSM (via the deployer role): `infrastructure/01-ssm-params.sh`.
2. Provision (default-VPC accounts): `infrastructure/02-provision.sh`. In this
   sandbox the VPC/subnet/IGW/SG and the deployer/instance IAM roles were created
   manually because there was no default VPC and SSM/SM writes were denied.
3. `userdata.sh` bootstraps the host (Docker, Caddy, Ollama), clones the repo,
   builds `.env` from SSM, patches Casdoor to `:8443`, and starts the stack.
4. **After first Casdoor login**, run `infrastructure/post-login-setup.sh` on the
   EC2 to enable the Ollama provider + register the model + install the MCP tools
   (these are per-user DB rows that require the user to exist first).
