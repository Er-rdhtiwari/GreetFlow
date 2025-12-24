variable "region" { type = string default = "ap-south-1" }
variable "domain_name" { type = string default = "rdhcloudlab.com" }

variable "cluster_name" { type = string default = "greetflow-prod-eks" }
variable "tags" { type = map(string) default = { project = "greetflow", env = "prod" } }
