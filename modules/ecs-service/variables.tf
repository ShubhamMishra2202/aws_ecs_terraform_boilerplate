variable "name" {
  type        = string
  description = "e.g. myapp-prod-web. Also the task definition family and log group suffix"
}

variable "cluster_id" {
  type = string
}

variable "image" {
  type        = string
  description = "Full image reference, e.g. <ecr-url>:prod"
}

variable "command" {
  type        = list(string)
  default     = null
  description = "Override the image CMD. Lets one image run as web, worker or migration"
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "cpu_architecture" {
  type        = string
  default     = "X86_64"
  description = "X86_64 or ARM64 (~20% cheaper; image must be built for arm64)"
}

variable "container_port" {
  type        = number
  default     = null
  description = "null for workers and one-off tasks"
}

variable "environment" {
  type        = map(string)
  default     = {}
  description = "Plain, non-secret env vars"
}

variable "secrets" {
  type        = map(string)
  default     = {}
  description = "ENV_NAME → SSM parameter name (e.g. /myapp-prod/api-key). Injected at container start"
}

variable "execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "log_retention_days" {
  type    = number
  default = 30
}

# ─── Service settings (ignored when create_service = false) ───────────────────
variable "create_service" {
  type        = bool
  default     = true
  description = "false = task definition only, for one-off `aws ecs run-task` jobs (migrations)"
}

variable "cluster_name" {
  type    = string
  default = null
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "max_count" {
  type        = number
  default     = null
  description = "Enables CPU/memory autoscaling between desired_count and this. null = fixed count"
}

variable "target_group_arn" {
  type        = string
  default     = null
  description = "Attach to an ALB target group. null = no load balancer (workers)"
}

variable "health_check_grace_seconds" {
  type    = number
  default = 60
}
