# ✅ PoC 1 Prompt (Copy-Paste): “GreetFlow” — New Year + Birthday Greeting (End-to-End Dev→Prod on EKS)

You are a **Senior Cloud/DevOps Architect + Full-Stack Engineer**.
Generate a **very small, production-style** PoC that teaches end-to-end flow:

✅ FastAPI backend  
✅ Next.js frontend  
✅ Docker images → ECR  
✅ Kubernetes (EKS) + Helm deployment  
✅ AWS Secrets Manager → Kubernetes Secret (via External Secrets Operator)  
✅ DNS-based dev/prod URL mapping (Route53 + ExternalDNS + ALB Ingress + ACM)  
✅ Terraform for infrastructure  
✅ Jenkins CI/CD with “build once → deploy dev → promote prod”  
✅ Ansible to bootstrap Jenkins agent tools

Keep it **simple**: **NO** Redis, Postgres, S3, OSS model.

---

## 0) Assumptions (use these without asking)
- AWS Region: `ap-south-1`
- Domain: `rdhcloudlab.com` (Hosted Zone already exists in Route53)
- We will use:
  - Dev URL: `greet-dev.rdhcloudlab.com`
  - Prod URL: `greet.rdhcloudlab.com`
- EKS cluster names:
  - `greetflow-dev-eks`
  - `greetflow-prod-eks`
- Namespaces:
  - `greetflow-dev`
  - `greetflow-prod`

---

## 1) App behavior (MVP)
### Backend (FastAPI)
Endpoints:
1. `GET /healthz` → `{ "ok": true }`
2. `POST /api/greet`
   Input JSON:
   {
     "name": "Radhe",
     "dob": "1995-01-10",
     "occasion": "new_year" | "birthday",
     "tone": "motivational" | "funny" | "formal"
   }

   Output JSON:
   {
     "message": "... greeting ...",
     "source": "openai" | "template",
     "env": "dev" | "prod"
   }

Logic:
- If env var `OPENAI_API_KEY` is present → generate via OpenAI (small prompt).
- Else → fallback to a deterministic **template** message.
- Add request id logging and basic input validation.

### Frontend (Next.js)
- Single page form (name, dob, occasion, tone)
- Submit → calls backend `/api/greet`
- Shows message + source + env
- UI reads API base URL from `NEXT_PUBLIC_API_BASE_URL`

---

## 2) Deliverables required (you MUST output all of these)
### A) Monorepo file tree (exact)
Create a repo called `greetflow-poc/` with:

greetflow-poc/
  apps/
    api/
      src/app/main.py
      src/app/settings.py
      src/app/greet.py
      tests/test_greet.py
      requirements.txt
      Dockerfile
    ui/
      package.json
      next.config.js
      pages/index.tsx
      pages/_app.tsx
      Dockerfile
  infra/
    terraform/
      modules/
        vpc/
        eks/
        ecr/
        iam_irsa/
        acm/
        addons/
      envs/
        dev/
          main.tf
          variables.tf
          outputs.tf
          terraform.tfvars.example
        prod/
          main.tf
          variables.tf
          outputs.tf
          terraform.tfvars.example
    helm/
      webapp/
        Chart.yaml
        values.yaml
        templates/
          api-deployment.yaml
          api-service.yaml
          ui-deployment.yaml
          ui-service.yaml
          ingress.yaml
          serviceaccount.yaml
          externalsecret.yaml
          hpa.yaml
      values-dev.yaml
      values-prod.yaml
  ci/
    Jenkinsfile
  ops/
    ansible/
      bootstrap_jenkins_agent.yml
  scripts/
    smoke_test.sh
    deploy_dev.sh
    promote_prod.sh
  README.md
  .gitignore

### B) Terraform (simple but production-shaped)
Terraform must create:
- VPC (public/private subnets, NAT)
- EKS cluster + managed node group
- ECR repos for `greetflow-api` and `greetflow-ui`
- IAM OIDC provider + IRSA roles needed for:
  - AWS Load Balancer Controller
  - ExternalDNS
  - External Secrets Operator (to read Secrets Manager)
- ACM certificate for `*.rdhcloudlab.com` (DNS validation via Route53)
- Add-ons installed via Helm provider in Terraform:
  - aws-load-balancer-controller
  - external-dns
  - external-secrets (ESO)

Keep Terraform modular but minimal (don’t overbuild).
Include outputs:
- `cluster_name`, `cluster_endpoint`, `ecr_api_repo_url`, `ecr_ui_repo_url`, `acm_cert_arn`

### C) Helm chart (reusable)
One chart deploys:
- api Deployment+Service
- ui Deployment+Service
- Ingress (ALB) with:
  - ACM cert ARN
  - ExternalDNS hostname
  - path routing:
    - `/api/*` → api service
    - `/*` → ui service
- ExternalSecret resource that maps AWS Secrets Manager secret into K8s Secret:
  - Dev: secret name `greetflow/dev/openai`
  - Prod: secret name `greetflow/prod/openai`
  - key inside secret: `OPENAI_API_KEY`
- HPA: (optional but include minimal HPA template with CPU target)

### D) Jenkins CI/CD (industry standard promotion)
Jenkinsfile must:
- run unit tests for API
- build Docker images (api, ui)
- push to ECR with tag = short git sha
- deploy to DEV via Helm (values-dev + image tags)
- run `scripts/smoke_test.sh` against `https://greet-dev.rdhcloudlab.com/healthz`
- manual approval input step
- deploy to PROD using the **same image tags**
- run smoke test on `https://greet.rdhcloudlab.com/healthz`

### E) Ansible bootstrap
One playbook that installs on Jenkins agent/runner:
- docker + permissions
- awscli v2
- kubectl
- helm
- terraform
- jq, git, python3

---

## 3) Secrets Manager integration requirements
- Use External Secrets Operator (ESO).
- Do NOT hardcode keys in repo.
- App should work even without OpenAI key (template fallback).
- In README, include AWS CLI command to create the secret:
  - greetflow/dev/openai
  - greetflow/prod/openai

---

## 4) Scripts required (must be complete, copy-paste ready)
- scripts/deploy_dev.sh
  - builds + pushes images OR assumes Jenkins built them (explain)
  - helm upgrade --install into `greetflow-dev`
- scripts/promote_prod.sh
  - deploys same tags to `greetflow-prod`
- scripts/smoke_test.sh
  - curls /healthz and POST /api/greet and validates HTTP 200

---

## 5) README must include (step-by-step)
1) Prereqs (AWS creds, domain hosted zone, terraform, kubectl, helm)
2) Terraform apply for dev then prod
3) Create secrets in Secrets Manager
4) Deploy via Jenkins OR manual scripts
5) How DNS + ALB + ExternalDNS works (short explanation)
6) Rollback steps (helm rollback)
7) Debug checklist (Ingress, ExternalDNS, ESO, pod logs)

---

## 6) Output format rules (important)
- First: show the **file tree**
- Then: provide content for each file in clearly labeled code blocks, e.g.
  - ```Dockerfile
  - ```python
  - ```yaml
  - ```hcl
- Make sure everything is consistent: names, ports, hosts, namespaces, chart values.

---

## 7) Minimal conventions (use these)
- API container port: 8000
- UI container port: 3000
- K8s service names:
  - api: `greetflow-api`
  - ui: `greetflow-ui`
- Helm release names:
  - dev: `greetflow-dev`
  - prod: `greetflow-prod`

Now generate the complete repo scaffold + all files + exact commands.
DO NOT ask clarifying questions. Use placeholders where needed, but keep runnable.
