variable "name" {
  type = string
}

variable "domain" {
  type        = string
  description = "Hostname served, e.g. app.example.com"
}

variable "certificate_arn" {
  type        = string
  description = "ACM cert in us-east-1 covering var.domain"
}

variable "routing" {
  type        = string
  default     = "spa"
  description = "spa = unknown paths serve /index.html (React/Vue). static = /about → /about/index.html (Next export, Hugo)"

  validation {
    condition     = contains(["spa", "static"], var.routing)
    error_message = "routing must be \"spa\" or \"static\"."
  }
}

variable "price_class" {
  type        = string
  default     = "PriceClass_100"
  description = "PriceClass_100 = US/EU edges only (cheapest)"
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Allow deleting the bucket with files in it (non-prod only)"
}
