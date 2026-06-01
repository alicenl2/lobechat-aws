#!/bin/bash
# EC2 bootstrap — runs once as root on first boot via cloud-init.
# Output: /var/log/lobechat-setup.log (+ cloud-init-output.log).
# On success it writes /var/log/lobechat-setup.done so you can poll for it.
set -euo pipefail
exec >> /var/log/lobechat-setup.log 2>&1
echo "=== lobechat setup started $(date -u +%FT%TZ) ==="

REGION=eu-west-1
DEPLOY_DIR=/opt/lobechat-aws
GITHUB_REPO_URL="GITHUB_REPO_PLACEHOLDER"   # substituted by 02-provision.sh
LOBE_HOST=alicenl-lobechat.duckdns.org
CASDOOR_HOST=alicenl-casdoor.duckdns.org
MINIO_HOST=alicenl-minio.duckdns.org

ssm_get() {  # $1 = param name (without /lobechat/ prefix); prints value or empty
	aws ssm get-parameter --name "/lobechat/$1" --with-decryption \
		--region "$REGION" --query Parameter.Value --output text 2>/dev/null || true
}

# ── 1. System packages ──────────────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg git jq unzip dnsutils

# ── 2. AWS CLI v2 ───────────────────────────────────────────────────────────
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp/awscli
/tmp/awscli/aws/install
rm -rf /tmp/awscli /tmp/awscliv2.zip

# ── 3. Docker CE ─────────────────────────────────────────────────────────────
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
	| gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
	> /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# ── 4. Caddy (installed now, started later once DNS is live) ──────────────────
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
	| gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
	> /etc/apt/sources.list.d/caddy-stable.list
apt-get update -y
apt-get install -y caddy
systemctl stop caddy || true   # don't let ACME fire before DNS is correct

# ── 5. Clone the (private) repo using a short-lived PAT ──────────────────────
GITHUB_PAT=$(ssm_get GITHUB_PAT)
if [ -z "$GITHUB_PAT" ]; then
	echo "FATAL: could not read /lobechat/GITHUB_PAT from SSM (check instance role)"; exit 1
fi
git clone "https://${GITHUB_PAT}@${GITHUB_REPO_URL#https://}" "$DEPLOY_DIR"
cd "$DEPLOY_DIR"
# Scrub the PAT from the stored remote so it isn't left on disk.
git remote set-url origin "$GITHUB_REPO_URL"
unset GITHUB_PAT

# ── 6. Build .env from SSM (secrets) + static config ─────────────────────────
aws ssm get-parameters-by-path --path /lobechat/ --with-decryption \
	--region "$REGION" --output json \
	| jq -r '.Parameters[]
		| select(.Name | test("GITHUB_PAT|DUCKDNS_TOKEN|ESADE_EMAIL") | not)
		| "\(.Name | split("/")[-1])=\(.Value)"' > .env

cat >> .env << ENVEOF
HOST_DOMAIN=${LOBE_HOST}
S3_BUCKET=lobe
AWS_REGION=${REGION}
AWS_DEFAULT_REGION=${REGION}
# MCP servers that need external creds are left blank (servers degrade gracefully)
SSH_HOST=
SSH_PORT=22
SSH_USERNAME=
SSH_ALLOWED_COMMANDS=ls,cat,head,tail,grep,find,ps,df,du,uptime,whoami,pwd,echo
SSH_ALLOWED_PATHS=/home,/tmp,/var/log
SSH_COMMANDS_BLACKLIST=rm,mv,dd,mkfs,fdisk,format,shutdown,reboot
SSH_ARGUMENTS_BLACKLIST=-rf,-fr,--force
OPENAPI_MCP_HEADERS=
ENVEOF

# ── 7. Patch Casdoor seed data + config with the public HTTPS URLs ───────────
sed -i "s|^origin = .*|origin = https://${CASDOOR_HOST}|" config/casdoor-app.conf

jq --arg cb "https://${LOBE_HOST}/api/auth/callback/casdoor" \
   --arg org "https://${CASDOOR_HOST}" '
	(.applications[] | select(.name=="lobechat") | .redirectUris) = [$cb] |
	(.applications[] | select(.name=="lobechat") | .origin)       = $org  |
	(.webhooks[]     | select(.name=="webhook_default") | .url)   = "http://lobe-chat:3210/api/webhooks/casdoor"
' config/init_data.json > config/init_data.json.tmp
mv config/init_data.json.tmp config/init_data.json

# Bind the login user's email to the ESADE address (for screenshot identity).
ESADE_EMAIL=$(ssm_get ESADE_EMAIL)
if [ -n "$ESADE_EMAIL" ] && [ "$ESADE_EMAIL" != "None" ]; then
	jq --arg em "$ESADE_EMAIL" '
		(.users[] | select(.owner=="lobechat" and .name=="user") | .email) = $em
	' config/init_data.json > config/init_data.json.tmp
	mv config/init_data.json.tmp config/init_data.json
fi

# ── 8. Data directories ──────────────────────────────────────────────────────
mkdir -p data/postgres data/minio data/qdrant data/mcphub config/ssh

# ── 9. DuckDNS: point all three subdomains at THIS instance (auto-detect IP) ──
DUCKDNS_TOKEN=$(ssm_get DUCKDNS_TOKEN)
echo "DUCKDNS_TOKEN=${DUCKDNS_TOKEN}" > /etc/lobechat-duckdns.env
chmod 600 /etc/lobechat-duckdns.env
cp infrastructure/duckdns-update.sh /usr/local/bin/duckdns-update.sh
chmod +x /usr/local/bin/duckdns-update.sh
DUCKDNS_TOKEN="$DUCKDNS_TOKEN" /usr/local/bin/duckdns-update.sh || true
(crontab -l 2>/dev/null; \
 echo "*/5 * * * * . /etc/lobechat-duckdns.env && /usr/local/bin/duckdns-update.sh") | crontab -

# ── 10. Wait for DNS to resolve to us BEFORE Caddy attempts ACME ─────────────
MY_IP=$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')
echo "this instance public IP = ${MY_IP}"
for host in "$LOBE_HOST" "$CASDOOR_HOST" "$MINIO_HOST"; do
	for i in $(seq 1 60); do
		R=$(dig +short "$host" A | tail -1)
		if [ "$R" = "$MY_IP" ]; then echo "DNS OK: $host -> $R"; break; fi
		echo "waiting for DNS $host (got '${R:-none}', want ${MY_IP}) [$i/60]"
		sleep 10
	done
done

# ── 11. Start Caddy (now ACME HTTP-01 will succeed) ──────────────────────────
cp infrastructure/Caddyfile /etc/caddy/Caddyfile
systemctl enable caddy
systemctl restart caddy

# ── 12. Launch the stack ─────────────────────────────────────────────────────
docker compose -f docker-compose.yml -f docker-compose.ec2.yml up -d

echo "=== lobechat setup finished $(date -u +%FT%TZ) ==="
touch /var/log/lobechat-setup.done
