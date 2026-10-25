variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type        = string
  description = "A private subnet"
}

variable "instance_type" {
  type    = string
  default = "t4g.nano"
}
