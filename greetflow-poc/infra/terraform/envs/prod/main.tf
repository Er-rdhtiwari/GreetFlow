terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.80" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.35" }
    helm = { source = "hashicorp/helm", version = "~> 2.16" }
  }
}

provider "aws" {
  region = var.region
}

data "aws_route53_zone" "root" {
  name         = "${var.domain_name}."
  private_zone = false
}

module "vpc" {
  source = "../../modules/vpc"
  name_prefix = "greetflow-prod"
  cidr = "10.30.0.0/16"
  azs  = ["ap-south-1a", "ap-south-1b"]
  public_subnets  = ["10.30.1.0/24", "10.30.2.0/24"]
  private_subnets = ["10.30.11.0/24", "10.30.12.0/24"]
  tags = var.tags
}

module "eks" {
  source = "../../modules/eks"
  cluster_name = var.cluster_name
  vpc_id = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  tags = var.tags
}

data "aws_eks_cluster" "this" {
  depends_on = [module.eks]
  name = module.eks.cluster_name
}
data "aws_eks_cluster_auth" "this" {
  depends_on = [module.eks]
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  token                  = data.aws_eks_cluster_auth.this.token
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    token                  = data.aws_eks_cluster_auth.this.token
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  }
}

# Reuse ECR + ACM created by dev env (build once -> promote same tags)
module "ecr" {
  source = "../../modules/ecr"
  create = false
}

module "acm" {
  source = "../../modules/acm"
  create = false
  domain_name = var.domain_name
  zone_id = data.aws_route53_zone.root.zone_id
}

module "iam_irsa" {
  source = "../../modules/iam_irsa"
  cluster_name = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  tags = var.tags
}

module "addons" {
  source = "../../modules/addons"
  cluster_name = module.eks.cluster_name
  region = var.region
  vpc_id  = module.vpc.vpc_id
  domain_filter = var.domain_name

  alb_role_arn = module.iam_irsa.alb_role_arn
  external_dns_role_arn = module.iam_irsa.external_dns_role_arn
  external_secrets_role_arn = module.iam_irsa.external_secrets_role_arn
}
