variable "create" {
  type    = bool
  default = true
}

variable "domain_name" {
  type = string
}

variable "zone_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
