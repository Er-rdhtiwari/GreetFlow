#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# fix_greetflow_dns_alb.sh
#
# Fixes the exact issues you hit:
#  1) AWS Load Balancer Controller IRSA role missing ec2:DescribeRouteTables (and others)
#  2) Route53 record for greet-dev.rdhcloudlab.com not (reliably) resolving from EC2
#  3) Ensures Route53 A/AAAA ALIAS points to the ALB from your Ingress
#  4) Flushes/restarts local DNS resolver on the EC2 (systemd-resolved)
#
# Requirements:
#  - aws cli configured on this EC2 (same account as the cluster)
#  - kubectl configured to talk to the EKS cluster
#  - permissions to create/attach IAM policy + update Route53
#
# Usage:
#   bash fix_greetflow_dns_alb.sh
#
# You can override defaults:
#   DOMAIN=rdhcloudlab.com SUBDOMAIN=greet-dev NAMESPACE=greetflow-dev INGRESS=greetflow bash fix_greetflow_dns_alb.sh
# -----------------------------------------------------------------------------

DOMAIN="${DOMAIN:-rdhcloudlab.com}"
SUBDOMAIN="${SUBDOMAIN:-greet-dev}"
FQDN="${FQDN:-${SUBDOMAIN}.${DOMAIN}}"

NAMESPACE="${NAMESPACE:-greetflow-dev}"
INGRESS="${INGRESS:-greetflow}"

ALB_SA_NS="${ALB_SA_NS:-kube-system}"
ALB_SA_NAME="${ALB_SA_NAME:-aws-load-balancer-controller}"
ALB_DEPLOY="${ALB_DEPLOY:-aws-load-balancer-controller}"

# IAM policy name to create (if missing) and attach to the role used by the ALB controller
POLICY_NAME="${POLICY_NAME:-AWSLoadBalancerControllerIAMPolicy}"

# Official policy json published by the controller project
# (Pin a version for stability; you can change v2.7.2 if you want)
POLICY_URL="${POLICY_URL:-https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json}"

log() { echo -e "\n==> $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1"; exit 1; }
}

log "Sanity checks"
need_cmd aws
need_cmd kubectl

# Optional deps for better verification
if ! command -v jq >/dev/null 2>&1; then
  log "Installing jq (optional but recommended)"
  sudo apt-get update -y >/dev/null
  sudo apt-get install -y jq >/dev/null
fi
if ! command -v dig >/dev/null 2>&1; then
  log "Installing dnsutils (for dig)"
  sudo apt-get update -y >/dev/null
  sudo apt-get install -y dnsutils >/dev/null
fi

log "AWS identity"
aws sts get-caller-identity

# -----------------------------------------------------------------------------
# 1) Fix ALB controller IRSA IAM permissions
# -----------------------------------------------------------------------------
log "Detect ALB Controller IRSA role from ServiceAccount: ${ALB_SA_NS}/${ALB_SA_NAME}"
ROLE_ARN="$(kubectl -n "${ALB_SA_NS}" get sa "${ALB_SA_NAME}" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || true)"

if [[ -z "${ROLE_ARN}" ]]; then
  log "ServiceAccount annotation not found. Falling back to parsing role from Ingress events..."
  # Try to parse assumed-role/<ROLE_NAME>/... from ingress describe
  ROLE_NAME_FALLBACK="$(kubectl -n "${NAMESPACE}" describe ingress "${INGRESS}" 2>/dev/null | \
    grep -oE 'assumed-role/[^/]+/' | head -n 1 | sed 's|assumed-role/||; s|/||' || true)"
  if [[ -z "${ROLE_NAME_FALLBACK}" ]]; then
    echo "ERROR: Could not detect ALB controller role ARN/name. Check ServiceAccount or Ingress events."
    exit 1
  fi
  ROLE_NAME="${ROLE_NAME_FALLBACK}"
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
else
  ROLE_NAME="${ROLE_ARN##*/}"
fi

log "ALB Controller Role ARN: ${ROLE_ARN}"
log "ALB Controller Role Name: ${ROLE_NAME}"

log "Ensure IAM policy ${POLICY_NAME} exists (create if missing)"
POLICY_ARN="$(aws iam list-policies --scope Local \
  --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn | [0]" --output text)"

if [[ "${POLICY_ARN}" == "None" || -z "${POLICY_ARN}" ]]; then
  TMP_POLICY="/tmp/alb_iam_policy.json"
  log "Downloading policy json: ${POLICY_URL}"
  curl -fsSL "${POLICY_URL}" -o "${TMP_POLICY}"

  log "Creating IAM policy: ${POLICY_NAME}"
  POLICY_ARN="$(aws iam create-policy \
    --policy-name "${POLICY_NAME}" \
    --policy-document "file://${TMP_POLICY}" \
    --query Policy.Arn --output text)"
else
  log "Policy already exists: ${POLICY_ARN}"
fi

log "Attach policy to role (if not attached)"
if aws iam list-attached-role-policies --role-name "${ROLE_NAME}" \
   --query "AttachedPolicies[?PolicyArn=='${POLICY_ARN}'] | length(@)" --output text | grep -q '^0$'; then
  aws iam attach-role-policy --role-name "${ROLE_NAME}" --policy-arn "${POLICY_ARN}"
  log "Attached ${POLICY_ARN} to ${ROLE_NAME}"
else
  log "Policy already attached to ${ROLE_NAME}"
fi

log "Restart ALB controller deployment to pick up IAM changes"
kubectl -n "${ALB_SA_NS}" rollout restart deploy/"${ALB_DEPLOY}" || true
kubectl -n "${ALB_SA_NS}" rollout status deploy/"${ALB_DEPLOY}" --timeout=180s || true

# -----------------------------------------------------------------------------
# 2) Get ALB DNS from Ingress (must exist)
# -----------------------------------------------------------------------------
log "Fetch ALB DNS from Ingress status: ${NAMESPACE}/${INGRESS}"
ALB_DNS="$(kubectl -n "${NAMESPACE}" get ingress "${INGRESS}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || true)"

if [[ -z "${ALB_DNS}" ]]; then
  echo "ERROR: Ingress has no .status.loadBalancer hostname yet."
  echo "Run: kubectl -n ${NAMESPACE} describe ingress ${INGRESS} (look for subnet tagging/IAM errors)."
  exit 1
fi

log "ALB DNS from Ingress: ${ALB_DNS}"

# -----------------------------------------------------------------------------
# 3) UPSERT Route53 A/AAAA ALIAS record to the ALB (don’t use CNAME)
# -----------------------------------------------------------------------------
log "Discover Route53 Hosted Zone for ${DOMAIN}"
HZ_ID="$(aws route53 list-hosted-zones-by-name --dns-name "${DOMAIN}" \
  --query "HostedZones[?Name=='${DOMAIN}.'].Id | [0]" --output text | sed 's|/hostedzone/||')"

if [[ -z "${HZ_ID}" || "${HZ_ID}" == "None" ]]; then
  echo "ERROR: Could not find hosted zone for ${DOMAIN} in this AWS account."
  exit 1
fi

log "Hosted Zone ID: ${HZ_ID}"

log "Get ALB CanonicalHostedZoneId by matching DNSName"
LB_INFO="$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?DNSName=='${ALB_DNS}'].[CanonicalHostedZoneId,DNSName] | [0]" \
  --output text || true)"

if [[ -z "${LB_INFO}" || "${LB_INFO}" == "None" ]]; then
  echo "ERROR: Could not find ELBv2 load balancer matching DNSName=${ALB_DNS}"
  echo "Try: aws elbv2 describe-load-balancers --query 'LoadBalancers[].DNSName' --output text | tr '\t' '\n' | head"
  exit 1
fi

ALB_HZ_ID="$(echo "${LB_INFO}" | awk '{print $1}')"
ALB_DNS_FROM_AWS="$(echo "${LB_INFO}" | awk '{print $2}')"

log "ALB CanonicalHostedZoneId: ${ALB_HZ_ID}"
log "ALB DNS (AWS confirm):      ${ALB_DNS_FROM_AWS}"

CHANGE_JSON="/tmp/route53-${SUBDOMAIN}-alias.json"
cat > "${CHANGE_JSON}" <<EOF
{
  "Comment": "UPSERT ${FQDN} -> ALB Alias",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${FQDN}.",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${ALB_HZ_ID}",
          "DNSName": "${ALB_DNS_FROM_AWS}.",
          "EvaluateTargetHealth": true
        }
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${FQDN}.",
        "Type": "AAAA",
        "AliasTarget": {
          "HostedZoneId": "${ALB_HZ_ID}",
          "DNSName": "${ALB_DNS_FROM_AWS}.",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF

log "Apply Route53 change batch (A + AAAA ALIAS)"
aws route53 change-resource-record-sets --hosted-zone-id "${HZ_ID}" --change-batch "file://${CHANGE_JSON}" >/dev/null
log "Route53 change submitted."

# -----------------------------------------------------------------------------
# 4) Fix EC2 local DNS resolver (so curl stops failing)
# -----------------------------------------------------------------------------
log "Flush local DNS caches (systemd-resolved if present)"
if command -v resolvectl >/dev/null 2>&1; then
  sudo resolvectl flush-caches || true
  sudo systemctl restart systemd-resolved || true

  # Ensure the primary interface uses the VPC resolver (169.254.169.253)
  IFACE="$(ip route show default | awk '{print $5; exit}')"
  if [[ -n "${IFACE}" ]]; then
    log "Set DNS on interface ${IFACE} to VPC resolver (169.254.169.253) + fallback (8.8.8.8)"
    sudo resolvectl dns "${IFACE}" 169.254.169.253 8.8.8.8 || true
  fi
else
  log "resolvectl not found; restarting networking and trying resolv.conf quick fix"
  sudo systemctl restart networking || true
fi

log "Current /etc/resolv.conf"
cat /etc/resolv.conf || true

# -----------------------------------------------------------------------------
# 5) Verify resolution + HTTP(S) health
# -----------------------------------------------------------------------------
log "Verify DNS resolution (from this EC2)"
echo "dig (default resolver):"
dig +short "${FQDN}" || true
echo "dig (VPC resolver 169.254.169.253):"
dig +short "${FQDN}" @169.254.169.253 || true
echo "dig (Google 8.8.8.8):"
dig +short "${FQDN}" @8.8.8.8 || true

log "Try health endpoint via HTTPS (your Ingress listens on 443)"
set +e
curl -sS -o /dev/null -w "HTTP %{http_code}\n" "https://${FQDN}/healthz"
RC=$?
set -e
if [[ $RC -ne 0 ]]; then
  echo "NOTE: curl failed. If DNS now resolves, check TLS/cert or ALB rules:"
  echo "  kubectl -n ${NAMESPACE} describe ingress ${INGRESS} | tail -n 60"
  exit 2
fi

log "DONE. If your smoke_test still fails, it is now an app/route issue (not DNS)."
