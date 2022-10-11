variable "github_organization" {
  description = "GitHub Organization"
  type        = string
  default     = ""
}

variable "github_repository" {
  description = "GitHub repository"
  type        = string
  default     = ""
}

variable "github_branch" {
  description = "GitHub branch"
  type        = string
  default     = ""
}

variable "github_token" {
  description = "GitHub token"
  type        = string
  default     = ""
}

variable "webhook_secret" {
  description = "Webhook secret"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = ""
}