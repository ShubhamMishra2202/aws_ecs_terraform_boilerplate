variable "name" {
  type = string
}

variable "container_insights" {
  type        = string
  default     = "disabled"
  description = "disabled | enabled | enhanced. enabled adds per-task metrics (extra CloudWatch cost)"
}

variable "ssm_parameter_prefix" {
  type        = string
  description = "Tasks may read SSM parameters under this path only, e.g. /myapp-prod"
}
