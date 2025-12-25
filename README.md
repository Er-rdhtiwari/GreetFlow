# GreetFlow PoC (Dev → Prod on EKS)

A very small, production-style PoC:
- FastAPI backend + Next.js UI
- Docker images in ECR
- EKS + Helm deployment
- Route53 + ExternalDNS + ALB Ingress + ACM wildcard TLS
- AWS Secrets Manager → External Secrets Operator → K8s Secret
- Jenkins pipeline: build once → deploy dev → smoke → approve → promote prod
- Ansible: bootstrap Jenkins agent tools

## URLs
- Dev: https://greet-dev.rdhcloudlab.com
- Prod: https://greet.rdhcloudlab.com

## Prereqs
- AWS creds configured (IAM user/role with EKS/ECR/Route53/ACM permissions)
- Route53 hosted zone already exists for `rdhcloudlab.com`
- Tools: terraform, awscli v2, kubectl, helm, docker, jq

---

## Step 1) Terraform apply (DEV first)

EKS cluster is being created in the same terraform apply, but the Kubernetes provider (used by kubernetes_manifest + helm_release) needs a working kube API endpoint + token at plan/apply time.

# Step 1: Create VPC + EKS only
```
cd infra/terraform/envs/dev
terraform init
terraform apply -auto-approve \
  -target=module.vpc \
  -target=module.eks
```

# Step 2:
```
aws secretsmanager create-secret \
  --name greetflow/dev/openai \
  --secret-string '{"OPENAI_API_KEY":"REPLACE_ME"}' \
  --region ap-south-1

aws secretsmanager create-secret \
  --name greetflow/prod/openai \
  --secret-string '{"OPENAI_API_KEY":"REPLACE_ME"}' \
  --region ap-south-1

```

# Step 3) Deploy DEV (manual)
```
export AWS_ACCOUNT_ID=<your-account-id>
export ACM_ARN=$(cd infra/terraform/envs/dev && terraform output -raw acm_cert_arn)

bash scripts/deploy_dev.sh <image_tag>
bash scripts/smoke_test.sh https://greet-dev.rdhcloudlab.com

```
# Step 4: Build & push images to ECR with that tag
```
export AWS_REGION=ap-south-1
export AWS_ACCOUNT_ID=253484721204
TAG=20251225-1

aws ecr get-login-password --region $AWS_REGION \
 | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# build + tag
docker build -t greetflow-api:$TAG ./api
docker tag greetflow-api:$TAG ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/greetflow-api:$TAG
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/greetflow-api:$TAG

docker build -t greetflow-ui:$TAG ./ui
docker tag greetflow-ui:$TAG ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/greetflow-ui:$TAG
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/greetflow-ui:$TAG


```

# Fix (best-practice) — attach the official AWS Load Balancer Controller IAM policy to the role

### A: Step A — confirm which IAM role your controller is using
```
kubectl -n kube-system get sa aws-load-balancer-controller \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'; echo
# It should match the role name seen in your error: greetflow-dev-eks-alb-controller
```
### Step B — create/attach the policy (CLI way)
```
curl -Lo iam_policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.17.0/docs/install/iam_policy.json

# Create policy once (skip if already exists)
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# Attach to the role used by IRSA
aws iam attach-role-policy \
  --role-name greetflow-dev-eks-alb-controller \
  --policy-arn arn:aws:iam::253484721204:policy/AWSLoadBalancerControllerIAMPolicy


```
### Step C — restart controller (forces quick re-reconcile)
```
kubectl -n kube-system rollout restart deploy/aws-load-balancer-controller


```
## Verify it’s fixed (you should see ALB ADDRESS appear)
```
kubectl -n greetflow-dev get ingress greetflow -w


### One more improvement (optional but recommended)
Your ingress shows Ingress Class: <none> even though you have the old annotation kubernetes.io/ingress.class: alb .
Switch to the new field to avoid edge cases:
```
kubectl -n greetflow-dev patch ingress greetflow --type merge \
  -p '{"spec":{"ingressClassName":"alb"}}'

```

```


# Important but can ignored as scipt issues has been resolved.
# Step 2: install ESO manually once
```
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

kubectl create ns external-secrets --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --set installCRDs=true

# confirm CRDs exist
kubectl get crd | grep external-secrets
kubectl get crd clustersecretstores.external-secrets.io

# now re-run terraform apply
# cd infra/terraform/envs/dev
# terraform apply -auto-approve

```

# Step 3

```
terraform import module.addons.helm_release.external_secrets external-secrets/external-secrets
terraform plan
terraform apply
```


### uninstall the existing release, then re-apply
```
helm -n external-secrets list
helm -n external-secrets uninstall external-secrets
kubectl delete ns external-secrets --wait=false 2>/dev/null || true

```
## OR: Option B — Import the existing Helm release into Terraform state
```
terraform import module.addons.helm_release.external_secrets external-secrets/external-secrets
terraform plan
terraform apply


```

### install ESO first, then re-run terraform
```bash
cd infra/terraform/envs/dev
terraform apply -auto-approve
terraform output
```