resource "aws_ecr_repository" "api" {
  count = var.create ? 1 : 0
  name  = var.repo_api_name
  force_delete = true
  tags  = var.tags
}

resource "aws_ecr_repository" "ui" {
  count = var.create ? 1 : 0
  name  = var.repo_ui_name
  force_delete = true
  tags  = var.tags
}

data "aws_ecr_repository" "api" {
  count = var.create ? 0 : 1
  name  = var.repo_api_name
}

data "aws_ecr_repository" "ui" {
  count = var.create ? 0 : 1
  name  = var.repo_ui_name
}
