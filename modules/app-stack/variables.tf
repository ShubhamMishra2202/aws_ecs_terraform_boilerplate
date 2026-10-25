# ─── Identity ─────────────────────────────────────────────────────────────────
variable "name" {
  type        = string
  description = "Project name, e.g. myapp. Keep it short: AWS caps some names at 32 chars"
}

variable "environment" {
  type        = string
  description = "e.g. staging, prod"
}

# ─── From global/ ─────────────────────────────────────────────────────────────
variable "ecr_repository_url" {
  type = string
}

variable "certificate_arn" {
  type = string
}

# ─── Network ──────────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  type        = string
  description = "/16 recommended. Must not overlap other environments"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "nat_type" {
  type    = string
  default = "instance"
}

# ─── App ──────────────────────────────────────────────────────────────────────
variable "image_tag" {
  type        = string
  description = "Moving tag the services track, e.g. staging or prod"
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "health_check_path" {
  type    = string
  default = "/health"
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
  type    = string
  default = "X86_64"
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "max_count" {
  type        = number
  default     = null
  description = "Autoscaling ceiling for the web service. null = no autoscaling"
}

variable "env_vars" {
  type        = map(string)
  default     = {}
  description = "Non-secret env vars for every container (web, worker, migrate)"
}

variable "secrets" {
  type        = map(string)
  default     = {}
  description = "ENV_NAME → SSM parameter name. Must live under /<name>-<environment>/ (execution role scope). Create them before applying"
}

variable "worker_command" {
  type        = list(string)
  default     = null
  description = "Run a background worker from the same image, e.g. [\"node\", \"worker.js\"]. null = no worker"
}

variable "migrate_command" {
  type        = list(string)
  default     = null
  description = "Task definition for one-off migrations, e.g. [\"npm\", \"run\", \"migrate\"]. null = none"
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "container_insights" {
  type    = string
  default = "disabled"
}

# ─── Database ─────────────────────────────────────────────────────────────────
variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_max_allocated_storage" {
  type    = number
  default = 100
}

variable "db_engine_version" {
  type    = string
  default = "17"
}

variable "db_parameter_group_family" {
  type    = string
  default = "postgres17"
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "db_backup_retention_days" {
  type    = number
  default = 7
}

variable "db_password_version" {
  type    = number
  default = 1
}

# ─── Safety ───────────────────────────────────────────────────────────────────
variable "protect_from_deletion" {
  type        = bool
  description = "true for prod: RDS/ALB deletion protection, final DB snapshot, no force-destroy"
}

# ─── Optional components ──────────────────────────────────────────────────────
variable "enable_bastion" {
  type    = bool
  default = true
}

variable "frontend_domain" {
  type        = string
  default     = null
  description = "Hostname for the S3 + CloudFront static site. null = no frontend"
}

variable "frontend_routing" {
  type    = string
  default = "spa"
}

variable "alarm_emails" {
  type    = list(string)
  default = []
}
