#!/bin/bash
# Store all LobeChat secrets + config in SSM Parameter Store under /lobechat/.
# Run ONCE from your laptop BEFORE launching the EC2 instance.
# Requires: aws CLI with credentials that allow ssm:PutParameter.
set -euo pipefail

REGION=eu-west-1

put() {  # $1 = name, $2 = value, $3 = type (SecureString|String)
	aws ssm put-parameter --region "$REGION" \
		--name "/lobechat/$1" --value "$2" --type "${3:-SecureString}" \
		--overwrite --no-cli-pager >/dev/null
	echo "  ok  /lobechat/$1"
}

echo "=== Generating random secrets ==="
POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=')
NEXT_AUTH_SECRET=$(openssl rand -base64 32)
KEY_VAULTS_SECRET=$(openssl rand -base64 32)
MINIO_ROOT_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=')

echo ""
echo "=== Values you must supply ==="
read -rp "OpenRouter API key (sk-or-v1-...): " OPENROUTER_KEY
read -rp "DuckDNS token (https://www.duckdns.org): " DUCKDNS_TOKEN
read -rp "GitHub PAT (repo read scope, to clone the private fork): " GITHUB_PAT
read -rp "ESADE email (shown in the LobeChat profile screenshot): " ESADE_EMAIL

echo ""
echo "=== Writing to SSM /lobechat/ ==="
put POSTGRES_PASSWORD   "$POSTGRES_PASSWORD"
put NEXT_AUTH_SECRET    "$NEXT_AUTH_SECRET"
put KEY_VAULTS_SECRET   "$KEY_VAULTS_SECRET"
put MINIO_ROOT_USER     "minioadmin"
put MINIO_ROOT_PASSWORD "$MINIO_ROOT_PASSWORD"
# Casdoor OAuth app id/secret — must match config/init_data.json (app 'lobechat').
put AUTH_CASDOOR_ID     "a387a4892ee19b1a2249"
put AUTH_CASDOOR_SECRET "dbf205949d704de81b0b5b3603174e23fbecc354"
put OPENROUTER_API_KEY  "$OPENROUTER_KEY"
put DUCKDNS_TOKEN       "$DUCKDNS_TOKEN"
put GITHUB_PAT          "$GITHUB_PAT"
put ESADE_EMAIL         "$ESADE_EMAIL" String

echo ""
echo "All parameters stored. Next: bash infrastructure/02-provision.sh"
