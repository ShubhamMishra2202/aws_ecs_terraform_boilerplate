variable "name" {
  type        = string
  description = "Project name. Prefixes every resource (ECR repo, IAM role, ...)"
}

variable "region" {
  type    = string
  default = "us-east-1" # CloudFront requires its certificate in us-east-1
}

variable "domain" {
  type        = string
  description = "Root domain, e.g. example.com. The certificate covers the apex and *.domain"
}

variable "validate_certificate" {
  type        = bool
  default     = false
  description = "Set true after the DNS validation records exist, then re-apply to wait for issuance"
}

variable "ecr_repositories" {
  type        = list(string)
  default     = ["app"]
  description = "One ECR repo per deployable image, created as <name>-<repo>"
}

variable "ecr_keep_images" {
  type        = number
  default     = 50
  description = "Tagged images kept per repo (your rollback history)"
}

variable "github_repository" {
  type        = string
  default     = null
  description = "owner/repo allowed to assume the CI deploy role via OIDC. null = skip CI role"
}
