#!/bin/bash
# Provision the EC2 instance for LobeChat. Run from the repo root AFTER
# 01-ssm-params.sh. Requires: aws CLI, jq.
#
# Override defaults via env vars, e.g.:
#   INSTANCE_TYPE=t3.xlarge KEY_NAME=vockey IAM_INSTANCE_PROFILE=LabInstanceProfile \
#     bash infrastructure/02-provision.sh
set -euo pipefail

REGION=eu-west-1
INSTANCE_TYPE=${INSTANCE_TYPE:-m5.xlarge}      # 4 vCPU / 16 GB, non-burstable, sandbox-friendly
VOLUME_SIZE=${VOLUME_SIZE:-60}                 # GB gp3 (spec minimum)
KEY_NAME=${KEY_NAME:-lobechat-key}
SG_NAME=${SG_NAME:-lobechat-sg}
# AWS Academy / sandbox accounts ship a ready instance profile; default to it.
IAM_INSTANCE_PROFILE=${IAM_INSTANCE_PROFILE:-LabInstanceProfile}
GITHUB_USERNAME=${GITHUB_USERNAME:-alicenl2}
GITHUB_REPO=${GITHUB_REPO:-lobechat-aws}

echo "Account: $(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo '??')"
echo "Region:  $REGION   Instance: $INSTANCE_TYPE   Profile: $IAM_INSTANCE_PROFILE"

# ── AMI: Ubuntu 24.04 LTS via SSM public parameter (no hardcoded AMI ID) ─────
AMI_ID=$(aws ssm get-parameter --region "$REGION" \
	--name "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id" \
	--query "Parameter.Value" --output text)
echo "AMI: $AMI_ID"

# ── SSH key pair ─────────────────────────────────────────────────────────────
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" &>/dev/null; then
	echo "Creating key pair $KEY_NAME..."
	aws ec2 create-key-pair --key-name "$KEY_NAME" --region "$REGION" \
		--query "KeyMaterial" --output text > ~/.ssh/${KEY_NAME}.pem
	chmod 600 ~/.ssh/${KEY_NAME}.pem
	echo "  saved ~/.ssh/${KEY_NAME}.pem"
else
	echo "Key pair $KEY_NAME exists (expecting private key at ~/.ssh/${KEY_NAME}.pem)"
fi

# ── Security group: 22 (your IP only), 80 + 443 (public) ─────────────────────
VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" \
	--filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)
SG_ID=$(aws ec2 describe-security-groups --region "$REGION" \
	--filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
	--query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "None")
if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
	echo "Creating security group $SG_NAME..."
	SG_ID=$(aws ec2 create-security-group --region "$REGION" \
		--group-name "$SG_NAME" --vpc-id "$VPC_ID" \
		--description "LobeChat EC2 — HTTP/HTTPS + SSH" --query "GroupId" --output text)
	MY_IP=$(curl -fsSL https://checkip.amazonaws.com)
	aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
		--protocol tcp --port 22  --cidr "${MY_IP}/32" >/dev/null
	aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
		--protocol tcp --port 80  --cidr "0.0.0.0/0" >/dev/null
	aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
		--protocol tcp --port 443 --cidr "0.0.0.0/0" >/dev/null
	# 8443: Casdoor served on the lobechat hostname (see docker-compose.ec2.yml)
	aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
		--protocol tcp --port 8443 --cidr "0.0.0.0/0" >/dev/null
	# Port 47000 is deliberately NOT opened — LobeChat is reachable only via Caddy.
	echo "  $SG_ID (22 from ${MY_IP}/32, 80+443+8443 public; 47000 closed)"
else
	echo "Security group $SG_NAME exists: $SG_ID"
fi

# ── Sanity-check the instance profile (read may be denied in sandboxes) ───────
if aws iam get-instance-profile --instance-profile-name "$IAM_INSTANCE_PROFILE" &>/dev/null; then
	echo "Instance profile $IAM_INSTANCE_PROFILE found."
else
	echo "WARN: cannot confirm instance profile '$IAM_INSTANCE_PROFILE' (IAM read may be"
	echo "      denied in this account). Proceeding — run-instances will fail clearly if"
	echo "      the name is wrong. Override with IAM_INSTANCE_PROFILE=<name>."
fi

# ── Render userdata (inject repo URL) ────────────────────────────────────────
REPO_URL="https://github.com/${GITHUB_USERNAME}/${GITHUB_REPO}.git"
sed "s|GITHUB_REPO_PLACEHOLDER|${REPO_URL}|g" \
	infrastructure/userdata.sh > /tmp/userdata-rendered.sh

# ── Launch ───────────────────────────────────────────────────────────────────
echo "Launching $INSTANCE_TYPE (${VOLUME_SIZE}GB gp3)..."
INSTANCE_ID=$(aws ec2 run-instances --region "$REGION" \
	--image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
	--key-name "$KEY_NAME" --security-group-ids "$SG_ID" \
	--iam-instance-profile "Name=${IAM_INSTANCE_PROFILE}" \
	--block-device-mappings \
		"DeviceName=/dev/sda1,Ebs={VolumeSize=${VOLUME_SIZE},VolumeType=gp3,DeleteOnTermination=true}" \
	--user-data "file:///tmp/userdata-rendered.sh" \
	--metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
	--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=lobechat-ec2}]" \
	--query "Instances[0].InstanceId" --output text)
echo "Instance: $INSTANCE_ID"

# ── Elastic IP (stable target for the DuckDNS records) ───────────────────────
EIP_ALLOC=$(aws ec2 allocate-address --region "$REGION" --domain vpc \
	--query "AllocationId" --output text)
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
aws ec2 associate-address --region "$REGION" \
	--instance-id "$INSTANCE_ID" --allocation-id "$EIP_ALLOC" >/dev/null
EIP=$(aws ec2 describe-addresses --region "$REGION" --allocation-ids "$EIP_ALLOC" \
	--query "Addresses[0].PublicIp" --output text)

cat <<EOF

════════════════════════════════════════════════════════════════
  Instance : $INSTANCE_ID
  EIP      : $EIP
  SSH      : ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@${EIP}

  DuckDNS: the three subdomains must EXIST in your account
  (alicenl-lobechat, alicenl-casdoor, alicenl-minio). You do NOT
  need to type the IP — the instance auto-points all three at
  itself every 5 min. Just confirm they exist, owned by your token.

  Bootstrap runs ~6-9 min. Watch it:
    ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@${EIP} 'tail -f /var/log/lobechat-setup.log'
  Done when this file appears:
    /var/log/lobechat-setup.done
════════════════════════════════════════════════════════════════
EOF
