variable "name" {
  type        = string
  description = "Resource name prefix, e.g. myapp-prod"
}

variable "cidr" {
  type        = string
  description = "VPC CIDR. Use a different, non-overlapping range per environment"
}

variable "azs" {
  type        = list(string)
  description = "At least 2 AZs (ALB and RDS subnet groups require it)"
}

variable "nat_type" {
  type        = string
  default     = "instance"
  description = "\"instance\" (~$4/mo, single point of failure) or \"gateway\" (~$32/mo + data, managed)"

  validation {
    condition     = contains(["instance", "gateway"], var.nat_type)
    error_message = "nat_type must be \"instance\" or \"gateway\"."
  }
}

variable "nat_instance_type" {
  type    = string
  default = "t4g.nano"
}
