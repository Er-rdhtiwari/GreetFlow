variable "cluster_name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "policy_arns" {
  description = "Managed policy ARNs to attach to the IRSA role"
  type        = list(string)
  default     = []
}
