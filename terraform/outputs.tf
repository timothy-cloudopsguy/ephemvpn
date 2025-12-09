# ECS outputs
output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs_cluster.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.ecs.service_name
}

output "ecs_task_definition_arn" {
  description = "ECS task definition ARN"
  value       = module.ecs.task_definition_arn
}

output "ecs_execution_role_arn" {
  description = "ECS execution role ARN"
  value       = module.ecs.execution_role_arn
}

output "ecs_task_role_arn" {
  description = "ECS task role ARN"
  value       = module.ecs.task_role_arn
}

output "ecs_security_group_id" {
  description = "ECS security group ID"
  value       = module.ecs.security_group_id
}

output "ecs_log_group_name" {
  description = "ECS CloudWatch log group name"
  value       = module.ecs.log_group_name
}

# Application outputs
output "app_name" {
  description = "Application name"
  value       = local.app_name
}

output "environment" {
  description = "Deployment environment"
  value       = local.env_name
}

# VPN outputs
output "master_api_key_parameter" {
  description = "SSM parameter name for master API key"
  value       = "/ephem-vpn/master-api-key"
}

output "wg_server_public_key_parameter" {
  description = "SSM parameter name for WireGuard server public key"
  value       = "/ephem-vpn/wg/server-public-key"
}

output "wg_listen_port" {
  description = "Port for WireGuard VPN server"
  value       = 51820
}

output "api_port" {
  description = "Port for VPN management API"
  value       = 8000
}
