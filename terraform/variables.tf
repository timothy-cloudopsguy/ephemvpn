variable "environment" {
  description = "Environment to deploy (matches properties.<env>.json)"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Optional override for app_name; defaults to value in properties file"
  type        = string
  default     = ""
}

