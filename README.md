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
```bash
cd infra/terraform/envs/dev
terraform init
terraform apply -auto-approve

terraform output
