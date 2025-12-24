# ✅ PoC 2 Prompt (Copy-Paste): “SpeakFlow” — Text-to-Speech (TTS) End-to-End Dev→Prod on EKS

You are a **Senior Cloud/DevOps Architect + Full-Stack Engineer**.
Generate a **very small, production-style** PoC that teaches end-to-end flow:

✅ FastAPI backend  
✅ Next.js frontend  
✅ Docker images → ECR  
✅ Kubernetes (EKS) + Helm deployment  
✅ IRSA (pod IAM role) to call AWS Polly securely (no static AWS keys)  
✅ AWS Secrets Manager → Kubernetes Secret (via External Secrets Operator) [for a simple API token]  
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
  - Dev URL: `speak-dev.rdhcloudlab.com`
  - Prod URL: `speak.rdhcloudlab.com`
- EKS cluster names:
  - `speakflow-dev-eks`
  - `speakflow-prod-eks`
- Namespaces:
  - `speakflow-dev`
  - `speakflow-prod`

---

## 1) App behavior (MVP)
### Backend (FastAPI)
Endpoints:
1) `GET /healthz` → `{ "ok": true }`

2) `POST /api/tts`
Input JSON:
{
  "text": "Happy New Year Radhe!",
  "voice": "Joanna"
}
Output:
- Return MP3 bytes with header `Content-Type: audio/mpeg`
- Also set header: `X-Env: dev|prod`

Security:
- Require a bearer token header:
  - `Authorization: Bearer <SPEAKFLOW_API_TOKEN>`
- The token must come from **AWS Secrets Manager**, synced via **External Secrets Operator** into a K8s Secret.
- If token missing/wrong → 401

AWS Integration (core learning):
- Use **boto3 Polly** `SynthesizeSpeech` to generate MP3.
- Use **IRSA** (K8s ServiceAccount annotated with IAM Role ARN) so the pod can call Polly securely.
- Required IAM policy: `polly:SynthesizeSpeech`

Fallback behavior:
- If Polly call fails, return a clear 500 with error + request id in logs.

### Frontend (Next.js)
- Single page with:
  - Text box, voice dropdown
  - “Speak” button
  - Plays returned MP3 in browser (HTML audio)
- UI reads:
  - `NEXT_PUBLIC_API_BASE_URL` (e.g., https://speak-dev.rdhcloudlab.com)
- UI sends bearer token:
  - Token is NOT hard-coded in code; for simplicity in PoC, read it from a UI runtime env var `NEXT_PUBLIC_SPEAKFLOW_TOKEN`
  - (This is for learning only; add a README note that real apps would NOT expose tokens client-side.)
  - OPTIONAL improvement: remove client token and rely on no-auth, but keep token to practice Secrets Manager + ESO.

---

## 2) Deliverables required (you MUST output all of these)
### A) Monorepo file tree (exact)
Create a repo called `speakflow-poc/` with:

speakflow-poc/
  apps/
    api/
      src/app/main.py
      src/app/settings.py
      src/app/tts.py
      src/app/auth.py
      tests/test_tts.py
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
        app_irsa_polly/          # IMPORTANT: IRSA role for the api to call Polly
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
          serviceaccount.yaml      # must support IRSA annotation
          externalsecret.yaml      # pulls SPEAKFLOW_API_TOKEN
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
- ECR repos for `speakflow-api` and `speakflow-ui`
- IAM OIDC provider + IRSA roles needed for:
  - AWS Load Balancer Controller
  - ExternalDNS
  - External Secrets Operator (read Secrets Manager)
  - **SpeakFlow API IRSA role with Polly permissions**
- ACM certificate for `*.rdhcloudlab.com` (DNS validation via Route53)
- Add-ons installed via Helm provider in Terraform:
  - aws-load-balancer-controller
  - external-dns
  - external-secrets (ESO)

Keep Terraform modular but minimal (don’t overbuild).
Include outputs:
- `cluster_name`, `cluster_endpoint`, `ecr_api_repo_url`, `ecr_ui_repo_url`, `acm_cert_arn`, `api_irsa_role_arn`

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
- ServiceAccount that:
  - is used by api Deployment
  - supports annotation: `eks.amazonaws.com/role-arn: <api_irsa_role_arn>`
- ExternalSecret resource mapping AWS Secrets Manager secret into K8s Secret:
  - Dev secret: `speakflow/dev/token` → key `SPEAKFLOW_API_TOKEN`
  - Prod secret: `speakflow/prod/token` → key `SPEAKFLOW_API_TOKEN`
- HPA: minimal template (CPU target)

### D) Jenkins CI/CD (industry standard promotion)
Jenkinsfile must:
- run unit tests for API
- build Docker images (api, ui)
- push to ECR with tag = short git sha
- deploy to DEV via Helm (values-dev + image tags)
- run `scripts/smoke_test.sh` against:
  - `https://speak-dev.rdhcloudlab.com/healthz`
  - `POST https://speak-dev.rdhcloudlab.com/api/tts` and validate:
    - HTTP 200
    - `Content-Type: audio/mpeg`
- manual approval input step
- deploy to PROD using the **same image tags**
- run smoke test on:
  - `https://speak.rdhcloudlab.com/healthz`
  - `POST https://speak.rdhcloudlab.com/api/tts` and validate mp3 response

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
- Do NOT hardcode token in repo.
- README must include AWS CLI commands to create:
  - `speakflow/dev/token` with key `SPEAKFLOW_API_TOKEN`
  - `speakflow/prod/token` with key `SPEAKFLOW_API_TOKEN`

---

## 4) Scripts required (must be complete, copy-paste ready)
- scripts/deploy_dev.sh
  - builds + pushes images OR assumes Jenkins built them (explain)
  - helm upgrade --install into `speakflow-dev`
- scripts/promote_prod.sh
  - deploys same tags to `speakflow-prod`
- scripts/smoke_test.sh
  - curls /healthz
  - posts to /api/tts with Authorization header (token read from env var)
  - validates audio/mpeg response

---

## 5) README must include (step-by-step)
1) Prereqs (AWS creds, domain hosted zone, terraform, kubectl, helm)
2) Terraform apply for dev then prod
3) Create Secrets Manager token secrets (dev/prod)
4) Deploy via Jenkins OR manual scripts
5) Explain:
   - IRSA in 5–8 lines (ServiceAccount → IAM role → Polly permission)
   - DNS + ALB + ExternalDNS in 5–8 lines
6) Rollback steps (helm rollback)
7) Debug checklist:
   - Ingress/ALB
   - ExternalDNS logs
   - ESO secret sync status
   - ServiceAccount annotation and IAM permissions
   - Pod logs

---

## 6) Output format rules (important)
- First: show the **file tree**
- Then: provide content for each file in clearly labeled code blocks:
  - ```Dockerfile
  - ```python
  - ```yaml
  - ```hcl
- Ensure everything is consistent: names, ports, hosts, namespaces, chart values.

---

## 7) Minimal conventions (use these)
- API container port: 8000
- UI container port: 3000
- K8s service names:
  - api: `speakflow-api`
  - ui: `speakflow-ui`
- Helm release names:
  - dev: `speakflow-dev`
  - prod: `speakflow-prod`

Now generate the complete repo scaffold + all files + exact commands.
DO NOT ask clarifying questions. Use placeholders where needed, but keep runnable.
