locals {
  wildcard = "*.${var.domain_name}"
}

resource "aws_acm_certificate" "wildcard" {
  count = var.create ? 1 : 0

  domain_name       = local.wildcard
  validation_method = "DNS"
  tags              = var.tags
}

resource "aws_route53_record" "validation" {
  for_each = var.create ? {
    for dvo in aws_acm_certificate.wildcard[0].domain_validation_options :
    dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  } : {}

  zone_id = var.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.value]
}

resource "aws_acm_certificate_validation" "wildcard" {
  count = var.create ? 1 : 0
  certificate_arn         = aws_acm_certificate.wildcard[0].arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

data "aws_acm_certificate" "wildcard" {
  count  = var.create ? 0 : 1
  domain = local.wildcard
  statuses = ["ISSUED"]
  most_recent = true
}
