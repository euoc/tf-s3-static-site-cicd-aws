provider "aws" {
  region = var.aws_region
}

provider "github" {
  token = var.github_token
  owner = var.github_organization
}