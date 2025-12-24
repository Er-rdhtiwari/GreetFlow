variable "create" { type = bool default = true }
variable "repo_api_name" { type = string default = "greetflow-api" }
variable "repo_ui_name"  { type = string default = "greetflow-ui" }
variable "tags" { type = map(string) default = {} }
