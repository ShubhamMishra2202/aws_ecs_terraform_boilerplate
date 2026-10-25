variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets in at least 2 AZs"
}

variable "db_name" {
  type    = string
  default = "app"
}

variable "username" {
  type    = string
  default = "app_admin"
}

variable "engine_version" {
  type    = string
  default = "17"
}

variable "parameter_group_family" {
  type        = string
  default     = "postgres17"
  description = "Must match the engine major version"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "max_allocated_storage" {
  type        = number
  default     = 100
  description = "Storage autoscaling ceiling. Storage can grow but never shrink"
}

variable "multi_az" {
  type        = bool
  default     = false
  description = "Standby in a second AZ with automatic failover. ~2x cost. Recommended for prod"
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "skip_final_snapshot" {
  type    = bool
  default = false
}

variable "apply_immediately" {
  type        = bool
  default     = false
  description = "false = disruptive changes wait for the maintenance window"
}

variable "password_ssm_parameter" {
  type        = string
  description = "SSM SecureString the generated password is written to, e.g. /myapp-prod/db-password"
}

variable "password_version" {
  type        = number
  default     = 1
  description = "Bump to rotate the password (then restart ECS services to pick it up)"
}
