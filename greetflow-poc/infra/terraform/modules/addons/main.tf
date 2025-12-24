resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set { name = "clusterName", value = var.cluster_name }
  set { name = "region",      value = var.region }
  set { name = "vpcId",       value = var.vpc_id }

  set { name = "serviceAccount.create", value = "true" }
  set { name = "serviceAccount.name",   value = "aws-load-balancer-controller" }
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

  set { name = "provider", value = "aws" }
  set { name = "policy",   value = "sync" }
  set { name = "txtOwnerId", value = var.cluster_name }
  set { name = "domainFilters[0]", value = var.domain_filter }

  set { name = "serviceAccount.create", value = "true" }
  set { name = "serviceAccount.name",   value = "external-dns" }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.external_dns_role_arn
  }
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  namespace  = "external-secrets"
  create_namespace = true

  set { name = "installCRDs", value = "true" }

  set { name = "serviceAccount.create", value = "true" }
  set { name = "serviceAccount.name",   value = "external-secrets" }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.external_secrets_role_arn
  }
}

# ClusterSecretStore used by app ExternalSecret
resource "kubernetes_manifest" "cluster_secret_store" {
  depends_on = [helm_release.external_secrets]

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-secretsmanager"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  }
}
