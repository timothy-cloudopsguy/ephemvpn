# ECS service outputs (created by this module)
output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.main.name
}

output "task_definition_arn" {
  description = "ECS task definition ARN"
  value       = aws_ecs_task_definition.main.arn
}

output "execution_role_arn" {
  description = "ECS execution role ARN (inherited from cluster module)"
  value       = var.ecs_execution_role_arn
}

output "task_role_arn" {
  description = "ECS task role ARN (created by this module)"
  value       = aws_iam_role.ecs_task_role.arn
}

output "security_group_id" {
  description = "ECS security group ID (created by this module)"
  value       = aws_security_group.ecs_sg.id
}

output "log_group_name" {
  description = "CloudWatch log group name (created by this module)"
  value       = aws_cloudwatch_log_group.ecs_logs.name
}
