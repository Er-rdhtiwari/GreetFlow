output "cert_arn" {
  value = var.create ? aws_acm_certificate_validation.wildcard[0].certificate_arn : data.aws_acm_certificate.wildcard[0].arn
}
