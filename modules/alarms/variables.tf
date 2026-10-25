variable "name" {
  type = string
}

variable "emails" {
  type        = list(string)
  default     = []
  description = "Each address must confirm the SNS subscription email"
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffix" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "service_names" {
  type        = list(string)
  description = "ECS services to watch for CPU/memory pressure"
}

variable "db_identifier" {
  type = string
}

variable "db_free_storage_threshold_gb" {
  type    = number
  default = 5
}
