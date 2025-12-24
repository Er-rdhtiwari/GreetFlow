output "api_repo_url" {
  value = var.create ? aws_ecr_repository.api[0].repository_url : data.aws_ecr_repository.api[0].repository_url
}
output "ui_repo_url" {
  value = var.create ? aws_ecr_repository.ui[0].repository_url : data.aws_ecr_repository.ui[0].repository_url
}
