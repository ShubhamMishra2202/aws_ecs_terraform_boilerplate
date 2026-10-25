variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type        = string
  description = "ALB egress is limited to the VPC"
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "certificate_arn" {
  type = string
}

variable "target_port" {
  type        = number
  description = "Container port the ALB forwards to"
}

variable "health_check_path" {
  type        = string
  default     = "/health"
  description = "Must return 200 without auth. Keep it cheap: no DB calls"
}

variable "deletion_protection" {
  type    = bool
  default = false
}
