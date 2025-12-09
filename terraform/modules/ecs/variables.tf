variable "app_name" {
  description = "Application name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}


variable "ecr_repository_url" {
  description = "ECR repository URL"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "ecs_execution_role_arn" {
  description = "ECS execution role ARN"
  type        = string
}

variable "fargate_cpu" {
  description = "Fargate CPU units (256, 512, 1024, etc.)"
  type        = string
  default     = "256"
}

variable "fargate_memory" {
  description = "Fargate memory in MB (512, 1024, 2048, etc.)"
  type        = string
  default     = "512"
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 1
}

variable "capacity_provider_strategy" {
  description = "Capacity provider strategy for ECS service"
  type = list(object({
    capacity_provider = string
    weight           = number
    base             = optional(number, 0)
  }))
  default = [
    {
      capacity_provider = "FARGATE_SPOT"
      weight           = 1
    }
  ]
}

variable "ssm_prefix" {
  description = "SSM parameter prefix for VPN configs"
  type        = string
  default     = "/ephem-vpn"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs"
  type        = list(string)
}

variable "runtime_platform" {
  description = "Runtime platform configuration for ECS task definition (optional - for ARM64 support)"
  type = object({
    cpu_architecture        = string
    operating_system_family = string
  })
  default = null
}

variable "wireguard" {
  description = "WireGuard server configuration"
  type = object({
    listen_port = optional(number, 51820)
    mtu         = optional(number, 1380)
    server_ip   = optional(string, "10.0.0.1/24")
    routes      = optional(string, "0.0.0.0/0")
  })
  default = {
    listen_port = 51820
    mtu         = 1380
    server_ip   = "10.0.0.1/24"
    routes      = "0.0.0.0/0"
  }
}

variable "public_ip" {
  description = "Public IP address of the VPN server (optional - will auto-detect if not provided)"
  type        = string
  default     = ""
}

variable "dns_name" {
  description = "DNS name for the VPN server (optional - Route53 record will be created if provided)"
  type        = string
  default     = ""
}

variable "route53_hosted_zone_id" {
  description = "Route53 hosted zone ID for DNS updates (required if dns_name is provided)"
  type        = string
  default     = ""
}