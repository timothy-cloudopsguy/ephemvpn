# ECS Cluster
resource "random_string" "suffix" {
  length  = 4
  special = false
  lower   = true
  upper   = false
  numeric = true
}

resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-${random_string.suffix.result}"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Name        = "${var.app_name}-${random_string.suffix.result}"
    Environment = var.environment
  }
}

# ECS Execution Role (used by ECS to run containers)
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.app_name}-execution-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-execution-${random_string.suffix.result}"
    Environment = var.environment
  }
}

# Attach execution role policy
resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
