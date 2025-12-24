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
```
cd infra/terraform/envs/dev
terraform init
# Step 1: Create VPC + EKS only
terraform apply -auto-approve \
  -target=module.vpc \
  -target=module.eks

# Step 2: Now apply everything (addons + helm + k8s manifests)
terraform apply -auto-approve
```



```
# install ESO manually once
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
cd infra/terraform/envs/dev
terraform apply -auto-approve

```
### uninstall the existing release, then re-apply
```
helm -n external-secrets list
helm -n external-secrets uninstall external-secrets
kubectl delete ns external-secrets --wait=false 2>/dev/null || true

```


### install ESO first, then re-run terraform
```bash
cd infra/terraform/envs/dev
terraform apply -auto-approve
terraform output
```