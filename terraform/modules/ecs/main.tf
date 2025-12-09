# ECS resources for this service
resource "random_string" "task_suffix" {
  length  = 4
  special = false
  lower   = true
  upper   = false
  numeric = true
}

# CloudWatch Log Group for this service
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${var.app_name}-${random_string.task_suffix.result}"
  retention_in_days = 30

  tags = {
    Name        = "${var.app_name}-${random_string.task_suffix.result}-logs"
    Environment = var.environment
  }
}

# ECS Task Role (for accessing SSM, etc.)
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.app_name}-task-${random_string.task_suffix.result}"

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
    Name        = "${var.app_name}-task-${random_string.task_suffix.result}"
    Environment = var.environment
  }
}

# SSM access policy for task role
resource "aws_iam_role_policy" "ecs_task_ssm_policy" {
  name = "${var.app_name}-ssm-policy-${random_string.task_suffix.result}"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter"
        ]
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_prefix}*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:DescribeParameters",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:GetChange"
        ]
        Resource = "arn:aws:route53:::hostedzone/*"
      }
    ]
  })
}

# Security group for this service
resource "aws_security_group" "ecs_sg" {
  name        = "${var.app_name}-sg-${random_string.task_suffix.result}"
  description = "Security group for ${var.app_name} ECS service"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.app_name}-sg-${random_string.task_suffix.result}"
    Environment = var.environment
  }
}

# Get current account ID for IAM policies
data "aws_caller_identity" "current" {}

# ECS Task Definition
resource "aws_ecs_task_definition" "main" {
  family                   = "${var.app_name}-task-${random_string.task_suffix.result}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  dynamic "runtime_platform" {
    for_each = var.runtime_platform != null ? [var.runtime_platform] : []
    content {
      cpu_architecture        = runtime_platform.value.cpu_architecture
      operating_system_family = runtime_platform.value.operating_system_family
    }
  }

  container_definitions = jsonencode([
    {
      name  = "app-container"
      image = "${var.ecr_repository_url}:latest"

      systemControls = [
        {
          namespace = "net.ipv4.ping_group_range"
          value     = "0 1000000000"
        }
      ]

      portMappings = [
        {
          containerPort = 51820
          hostPort      = 51820
          protocol      = "udp"
        },
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]

      environment = concat([
        {
            name = "DEBUG"
            value = "1"
        },
        {
          name  = "SSM_PREFIX"
          value = var.ssm_prefix
        },
        {
          name  = "AWS_REGION"
          value = var.region
        },
        {
          name  = "API_PORT"
          value = "8000"
        },
        {
          name  = "WG_LISTEN_PORT"
          value = tostring(var.wireguard.listen_port)
        },
        {
          name  = "WG_MTU"
          value = tostring(var.wireguard.mtu)
        },
        {
          name  = "WG_ROUTES"
          value = var.wireguard.routes
        },
        {
          name  = "POOLING"
          value = "1"
        },
        {
          name  = "PROCESSOR_WORKERS"
          value = "4"
        },
        {
          name  = "PROCESSOR_QUEUE_CAP"
          value = "1000"
        },
        {
          name  = "WG_TUN_QUEUE_CAP"
          value = "1024"
        },
        {
          name  = "TCP_ACK_DELAY_MS"
          value = "5"
        }
      ], var.public_ip != "" ? [
        {
          name  = "VPN_PUBLIC_IP"
          value = var.public_ip
        }
      ] : [], var.dns_name != "" ? [
        {
          name  = "DNS_NAME"
          value = var.dns_name
        }
      ] : [], var.route53_hosted_zone_id != "" ? [
        {
          name  = "ROUTE53_HOSTED_ZONE_ID"
          value = var.route53_hosted_zone_id
        }
      ] : [])

      # WireGuard keys are now generated by the container itself
      # No secrets needed as the container handles SSM access directly

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      essential = true

      # Enable init process for ECS Exec
      initProcessEnabled = true

      # Health check for the API
      healthCheck = {
        command = [
          "CMD-SHELL",
          "uptime || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = {
    Name        = "${var.app_name}-task-${random_string.task_suffix.result}"
    Environment = var.environment
  }
}

# CloudWatch Log Group
resource "aws_ecs_service" "main" {
  name                   = "${var.app_name}-service-${random_string.task_suffix.result}"
  cluster                = var.ecs_cluster_name
  task_definition        = aws_ecs_task_definition.main.arn
  desired_count          = var.desired_count
  enable_execute_command = true

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider_strategy[0].capacity_provider
    weight            = 100
  }

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  tags = {
    Name        = "${var.app_name}-service-${random_string.task_suffix.result}"
    Environment = var.environment
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}
