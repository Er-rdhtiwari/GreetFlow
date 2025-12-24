variable "cluster_name" { type = string }
variable "region" { type = string }
variable "vpc_id" { type = string }
variable "domain_filter" { type = string } # rdhcloudlab.com

variable "alb_role_arn" { type = string }
variable "external_dns_role_arn" { type = string }
variable "external_secrets_role_arn" { type = string }
