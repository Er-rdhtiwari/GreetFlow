# Uses terraform-aws-modules/iam to create IRSA roles for addons.
# Keeps this PoC minimal but aligned to industry patterns.

resource "aws_iam_policy" "external_dns" {
  name        = "${var.cluster_name}-external-dns"
  description = "ExternalDNS Route53 access"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "route53:ChangeResourceRecordSets"
        ],
        Resource = ["arn:aws:route53:::hostedzone/*"]
      },
      {
        Effect = "Allow",
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource"
        ],
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_policy" "external_secrets" {
  name        = "${var.cluster_name}-external-secrets"
  description = "External Secrets Operator SecretsManager access"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets"
        ],
        Resource = ["*"]
      },
      {
        Effect = "Allow",
        Action = ["kms:Decrypt"],
        Resource = ["*"]
      }
    ]
  })
}

module "irsa_alb" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.47.0"

  role_name                              = "${var.cluster_name}-alb-controller"
  attach_load_balancer_controller_policy  = true

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = var.tags
}

module "irsa_external_dns" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.47.0"

  role_name = "${var.cluster_name}-external-dns"
  role_policy_arns = {
    external_dns = aws_iam_policy.external_dns.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }

  tags = var.tags
}

module "irsa_external_secrets" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.47.0"

  role_name = "${var.cluster_name}-external-secrets"
  role_policy_arns = {
    external_secrets = aws_iam_policy.external_secrets.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "extra" {
  for_each   = toset(var.policy_arns)
  role       = aws_iam_role.this.name
  policy_arn = each.value
}
