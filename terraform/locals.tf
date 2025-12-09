locals {
  # Load the existing properties files from the cdk directory (properties.dev.json / properties.prod.json)
  props = jsondecode(file("${path.module}/properties.${var.environment}.json"))

  # Expose useful values
  env_name = var.environment
  app_name = length(trimspace(var.app_name)) > 0 ? var.app_name : "${local.props.app_name}${title(var.environment)}"
  route53  = local.props.route53
  region   = length(trimspace(var.region)) > 0 ? var.region : ""

  # DNS configuration
  vpn_dns_name          = "${lower(local.app_name)}.${local.props.route53.domain_name}"
  route53_hosted_zone_id = data.aws_route53_zone.selected.zone_id
} 