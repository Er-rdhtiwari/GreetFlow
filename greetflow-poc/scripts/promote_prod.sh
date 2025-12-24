#!/usr/bin/env bash
set -euo pipefail

TAG="${1:?Usage: promote_prod.sh <image_tag>}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
CLUSTER="${PROD_CLUSTER:-greetflow-prod-eks}"
NS="greetflow-prod"

ACCOUNT_ID="${AWS_ACCOUNT_ID:?Set AWS_ACCOUNT_ID}"
API_REPO="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/greetflow-api"
UI_REPO="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/greetflow-ui"

ACM_ARN="${ACM_ARN:?Set ACM_ARN (wildcard cert arn)}"

aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER}"

kubectl get ns "${NS}" >/dev/null 2>&1 || kubectl create ns "${NS}"

helm upgrade --install greetflow-prod infra/helm/webapp \
  -n "${NS}" \
  -f infra/helm/values-prod.yaml \
  --set image.api.repository="${API_REPO}" \
  --set image.api.tag="${TAG}" \
  --set image.ui.repository="${UI_REPO}" \
  --set image.ui.tag="${TAG}" \
  --set ingress.acmCertArn="${ACM_ARN}" \
  --wait --timeout 10m --atomic

echo "✅ Deployed PROD with tag ${TAG}"
