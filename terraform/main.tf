
# ECS Cluster module
module "ecs_cluster" {
  source = "./modules/ecs_cluster"

  app_name    = local.app_name
  environment = local.env_name
  region      = var.region
}

# Data sources for default VPC and public subnets
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

# ECR Repository (referenced by keygen task)
data "aws_ecr_repository" "repo" {
  name = local.props.ecr.repository_name
}

# Route53 Hosted Zone lookup
data "aws_route53_zone" "selected" {
  name         = local.props.route53.domain_name
  private_zone = false
}

# ECS Fargate deployment for Ephemeral VPN
module "ecs" {

  source = "./modules/ecs"

  app_name    = local.app_name
  environment = local.env_name
  region      = var.region

  # ECR repository (use the data source)
  ecr_repository_url = data.aws_ecr_repository.repo.repository_url

  # Fargate configuration from properties
  fargate_cpu                = local.props.ecs.fargate_cpu
  fargate_memory             = local.props.ecs.fargate_memory
  desired_count              = local.props.ecs.desired_count
  capacity_provider_strategy = local.props.ecs.capacity_provider_strategy
  runtime_platform           = lookup(local.props.ecs, "runtime_platform", null)

  # WireGuard configuration from properties
  wireguard = lookup(local.props, "wireguard", {})

  # Network configuration from default VPC
  vpc_id            = data.aws_vpc.default.id
  public_subnet_ids = data.aws_subnets.public.ids

  # SSM prefix for VPN configs
  ssm_prefix = "/ephem-vpn"

  # Public IP (optional - auto-detection will be used if not provided)
  public_ip = lookup(local.props.ecs, "public_ip", "")

  # Route53 DNS configuration (dynamically created)
  dns_name = local.vpn_dns_name
  route53_hosted_zone_id = local.route53_hosted_zone_id

  # Cluster and execution role from cluster module
  ecs_cluster_name       = module.ecs_cluster.cluster_name
  ecs_execution_role_arn = module.ecs_cluster.execution_role_arn
}

# Note: WireGuard keys should be generated manually or through CI/CD for security
# To generate keys, you can temporarily enable the keygen task or run manually:
# docker run --rm -e SSM_PREFIX=/ephem-vpn -e AWS_REGION=us-east-2 --entrypoint /usr/local/bin/keygen.sh <your-image>


