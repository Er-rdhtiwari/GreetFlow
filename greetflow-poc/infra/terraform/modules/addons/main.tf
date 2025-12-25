resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }
  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.alb_role_arn
  }
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = "kube-system"

  set {
    name  = "provider.name"
    value = "aws"
  }
  set {
    name  = "policy"
    value = "sync"
  }
  set {
    name  = "txtOwnerId"
    value = var.cluster_name
  }
  set {
    name  = "domainFilters[0]"
    value = var.domain_filter
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "external-dns"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.external_dns_role_arn
  }
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  # Make Helm behave like your CLI command: --wait --timeout
  wait    = true
  atomic  = true
  timeout = 600

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "external-secrets"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.external_secrets_role_arn
  }
}

# REAL wait: CRD must exist + be Established before we create ClusterSecretStore
resource "null_resource" "wait_for_external_secrets_crds" {
  depends_on = [helm_release.external_secrets]

  # Rerun only if you change key inputs (optional but good practice)
  triggers = {
    role_arn = var.external_secrets_role_arn
    region   = var.region
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command = <<-EOT
      set -euo pipefail
      ns="external-secrets"

      for crd in \
        clustersecretstores.external-secrets.io \
        secretstores.external-secrets.io \
        externalsecrets.external-secrets.io
      do
        echo "Waiting for CRD: $crd"
        until kubectl get crd "$crd" >/dev/null 2>&1; do sleep 2; done
        kubectl wait --for=condition=Established --timeout=5m "crd/$crd" >/dev/null
      done

      # Optional: ensure controller is actually up
      kubectl -n "$ns" wait --for=condition=Available deploy --all --timeout=5m >/dev/null
      echo "External Secrets CRDs + deployments are ready."
    EOT
  }
}

# Remove this (it fails at plan time):
# resource "kubernetes_manifest" "cluster_secret_store" { ... }

resource "null_resource" "cluster_secret_store" {
  depends_on = [null_resource.wait_for_external_secrets_crds]

  triggers = {
    region   = var.region
    role_arn = var.external_secrets_role_arn
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command = <<-EOT
      set -euo pipefail

      until kubectl -n external-secrets get sa external-secrets >/dev/null 2>&1; do sleep 2; done

      rm -rf "$HOME/.kube/cache/discovery" "$HOME/.kube/http-cache" || true

      for i in {1..90}; do
        if kubectl api-resources --api-group=external-secrets.io 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "clustersecretstores"; then
          break
        fi
        sleep 2
      done

      # Get served versions as a space-separated list (e.g. "v1 v1beta1")
      served="$(kubectl get crd clustersecretstores.external-secrets.io -o jsonpath='{.spec.versions[?(@.served==true)].name}' | tr -d '\r' || true)"

      if [ -z "$served" ]; then
        echo "ERROR: Could not read served versions from CRD clustersecretstores.external-secrets.io"
        kubectl get crd clustersecretstores.external-secrets.io -o yaml | sed -n '1,160p' || true
        exit 1
      fi

      if echo " $served " | grep -q " v1 "; then
        ver="v1"
      elif echo " $served " | grep -q " v1beta1 "; then
        ver="v1beta1"
      elif echo " $served " | grep -q " v1alpha1 "; then
        ver="v1alpha1"
      else
        ver="$(awk '{print $1}' <<<"$served")"
      fi

      echo "Using ClusterSecretStore apiVersion: external-secrets.io/$ver"
      echo "Served versions were: $served"

      cat <<YAML | kubectl apply -f -
      apiVersion: external-secrets.io/$ver
      kind: ClusterSecretStore
      metadata:
        name: aws-secretsmanager
      spec:
        provider:
          aws:
            service: SecretsManager
            region: ${var.region}
            auth:
              jwt:
                serviceAccountRef:
                  name: external-secrets
                  namespace: external-secrets
      YAML

      kubectl get clustersecretstore aws-secretsmanager -o yaml >/dev/null
      echo "ClusterSecretStore created/updated."
    EOT
  }
}
