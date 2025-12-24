output "alb_role_arn"            { value = module.irsa_alb.iam_role_arn }
output "external_dns_role_arn"   { value = module.irsa_external_dns.iam_role_arn }
output "external_secrets_role_arn" { value = module.irsa_external_secrets.iam_role_arn }
