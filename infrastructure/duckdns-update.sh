#!/bin/bash
# Updates all three DuckDNS A-records to this machine's current public IP.
# DUCKDNS_TOKEN must be in the environment (loaded from /etc/lobechat-duckdns.env by cron).
set -euo pipefail

DOMAINS="alicenl-lobechat,alicenl-casdoor,alicenl-minio"
LOG=/var/log/duckdns.log

if [ -z "${DUCKDNS_TOKEN:-}" ]; then
    echo "[$(date -u +%FT%TZ)] ERROR: DUCKDNS_TOKEN not set" >> "$LOG"
    exit 1
fi

RESPONSE=$(curl -fsSL \
    "https://www.duckdns.org/update?domains=${DOMAINS}&token=${DUCKDNS_TOKEN}&ip=")

echo "[$(date -u +%FT%TZ)] $RESPONSE" >> "$LOG"
