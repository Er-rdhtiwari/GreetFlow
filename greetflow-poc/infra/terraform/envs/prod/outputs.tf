output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "ecr_api_repo_url" { value = module.ecr.api_repo_url }
output "ecr_ui_repo_url"  { value = module.ecr.ui_repo_url }
output "acm_cert_arn"     { value = module.acm.cert_arn }
output "hosted_zone_id"   { value = data.aws_route53_zone.root.zone_id }
