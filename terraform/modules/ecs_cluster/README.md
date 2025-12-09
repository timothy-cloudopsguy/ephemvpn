# ECS Cluster Module

This module creates the shared ECS cluster and execution role infrastructure that can be used by multiple ECS services.

## Features

- ECS cluster with configurable settings
- ECS execution role with basic permissions
- Modular design for reuse across services

## Usage

```hcl
module "ecs_cluster" {
  source = "./modules/ecs_cluster"

  app_name    = "my-app"
  environment = "dev"
  region      = "us-east-1"
}
```

## Outputs

- `cluster_name`: ECS cluster name
- `cluster_id`: ECS cluster ID
- `execution_role_arn`: ARN of the ECS execution role
- `execution_role_name`: Name of the ECS execution role

## Security

The execution role includes basic ECS task execution permissions. Additional permissions should be added as needed by individual service modules.
