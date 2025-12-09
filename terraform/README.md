# Ephemeral VPN - Terraform Infrastructure

This Terraform configuration deploys the Ephemeral VPN Docker container to AWS ECS Fargate with Fargate Spot for cost optimization.

## Architecture

- **ECS Cluster**: Fargate cluster running the VPN container
- **ECS Service**: Service with Fargate Spot capacity provider
- **Networking**: Runs on public subnets with security groups for VPN (UDP 1194) and API (TCP 8000)
- **Storage**: Configurations stored in AWS SSM Parameter Store
- **Logging**: CloudWatch logs for container logs
- **IAM**: Task roles with SSM access for configuration management

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **ECR Repository** - The container image must be pushed to ECR
3. **VPC Infrastructure** - VPC with public subnets
4. **Terraform** >= 1.4.0

## Configuration

### Properties File (properties.dev.json)

```json
{
  "app_name": "ephemVpn",
  "ecr": {
    "repository_region": "us-east-1",
    "repository_account": "458960552625",
    "repository_name": "ephem/vpn"
  },
  "route53": {
    "domain_name": "dev.ephemvpn.com",
    "short_domain": "dev.ephemvpn.com",
    "ttl": 60
  },
  "ecs": {
    "fargate_cpu": "256",
    "fargate_memory": "512",
    "desired_count": 1,
    "capacity_provider_strategy": [
      {
        "capacity_provider": "FARGATE_SPOT",
        "weight": 1
      }
    ]
  }
}
```

### Environment Variables

The ECS task automatically sets these environment variables:
- `SSM_PREFIX`: `/ephem-vpn` (SSM parameter prefix)
- `AWS_REGION`: Current region
- `API_PORT`: `8000`
- `VPN_PORT`: `1194`
- `VPN_PROTO`: `udp`

## Deployment

### 1. Initialize Terraform

```bash
cd terraform
terraform init
```

### 2. Plan Deployment

```bash
terraform plan -var="environment=dev"
```

### 3. Apply Deployment

```bash
terraform apply -var="environment=dev"
```

## Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `environment` | Environment (dev/prod) | `dev` |
| `region` | AWS region | `us-east-1` |

**Note**: The deployment automatically uses the default VPC and its public subnets. If you need to use a different VPC, you can modify the data sources in `main.tf`.

## Outputs

After deployment, Terraform will output:

- `ecs_cluster_name`: ECS cluster name
- `ecs_service_name`: ECS service name
- `ecs_task_definition_arn`: Task definition ARN
- `ecs_security_group_id`: Security group for the service
- `ecs_log_group_name`: CloudWatch log group name

## Accessing the Service

### VPN Connection

The OpenVPN service runs on UDP port 1194. Get the public IP of the ECS task:

```bash
# Get task public IP
aws ecs describe-tasks \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --tasks $(aws ecs list-tasks --cluster $(terraform output -raw ecs_cluster_name) --query 'taskArns[0]' --output text) \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text | \
  xargs aws ec2 describe-network-interfaces --network-interface-ids --query 'NetworkInterfaces[0].Association.PublicIp' --output text
```

### Management API

The REST API runs on port 8000 at the same public IP. Use the API key from SSM:

```bash
# Get API key
API_KEY=$(aws ssm get-parameter --name "/ephem-vpn/api-key" --with-decryption --query 'Parameter.Value' --output text)

# Create a client
curl -X POST http://<TASK_IP>:8000/clients \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"client_id": "user1"}'
```

## Security Considerations

- **Fargate Spot**: Uses spot instances for cost savings (may be interrupted)
- **Public Access**: Both VPN and API ports are open to 0.0.0.0/0
- **SSM Access**: Task role has SSM parameter access scoped to `/ephem-vpn*`
- **Logs**: All container logs sent to CloudWatch

## Cost Optimization

- **Fargate Spot**: Up to 70% cost savings vs On-Demand
- **Small Instance**: 256 CPU / 512 MB RAM (minimal for VPN server)
- **Auto-scaling**: Can be configured for scaling to zero when not needed

## Troubleshooting

### Check Service Status

```bash
# Service health
aws ecs describe-services --cluster $(terraform output -raw ecs_cluster_name) --services $(terraform output -raw ecs_service_name)

# Task status
aws ecs describe-tasks --cluster $(terraform output -raw ecs_cluster_name) --tasks $(aws ecs list-tasks --cluster $(terraform output -raw ecs_cluster_name) --query 'taskArns[0]' --output text)
```

### View Logs

```bash
# Container logs
aws logs tail $(terraform output -raw ecs_log_group_name) --follow
```

### Common Issues

1. **Task fails to start**: Check IAM permissions and SSM parameters
2. **Can't connect to VPN**: Verify security groups and task networking
3. **API returns 401**: Check API key in SSM Parameter Store

## Scaling

To scale the service:

```bash
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw ecs_service_name) \
  --desired-count 2
```

## Cleanup

```bash
terraform destroy -var="environment=dev"
```