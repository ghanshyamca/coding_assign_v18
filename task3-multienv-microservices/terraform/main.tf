##############################################################################
# Workspace guard
# Every environment MUST run in an explicit workspace (dev/staging/prod).
# Running in the "default" workspace would silently mix state, so we hard-fail.
##############################################################################
locals {
  is_default_workspace = terraform.workspace == "default"
}

resource "null_resource" "workspace_guard" {
  count = local.is_default_workspace ? 1 : 0

  # This provisioner-free resource never actually gets created because the
  # precondition below aborts the plan first with a readable message.
  lifecycle {
    precondition {
      condition     = !local.is_default_workspace
      error_message = "Refusing to run in the 'default' workspace. Run: terraform workspace select <dev|staging|prod>."
    }
  }
}

##############################################################################
# Per-environment configuration selected by terraform.workspace
##############################################################################
locals {
  env = terraform.workspace

  env_config = {
    dev = {
      cidr           = "10.10.0.0/16"
      node_type      = "t3.small"
      min_size       = 1
      desired_size   = 2
      max_size       = 3
      single_nat     = true
      cluster_suffix = "dev"
    }
    staging = {
      cidr           = "10.20.0.0/16"
      node_type      = "t3.medium"
      min_size       = 2
      desired_size   = 2
      max_size       = 4
      single_nat     = true
      cluster_suffix = "staging"
    }
    prod = {
      cidr           = "10.30.0.0/16"
      node_type      = "t3.large"
      min_size       = 3
      desired_size   = 4
      max_size       = 8
      single_nat     = false
      cluster_suffix = "prod"
    }
  }

  # Falls back to dev config only so that `terraform validate` in an unselected
  # workspace does not crash; real runs are guarded above.
  cfg = lookup(local.env_config, local.env, local.env_config["dev"])

  cluster_name = "${var.base_name}-${local.cfg.cluster_suffix}"

  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Project     = var.base_name
    Environment = local.env
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

##############################################################################
# Networking
##############################################################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.cluster_name}-vpc"
  cidr = local.cfg.cidr

  azs             = local.azs
  private_subnets = [for i, az in local.azs : cidrsubnet(local.cfg.cidr, 4, i)]
  public_subnets  = [for i, az in local.azs : cidrsubnet(local.cfg.cidr, 4, i + 8)]

  enable_nat_gateway     = true
  single_nat_gateway     = local.cfg.single_nat
  one_nat_gateway_per_az = !local.cfg.single_nat
  enable_dns_hostnames   = true

  # Tags required by the AWS Load Balancer controller / EKS subnet discovery.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  tags = local.tags
}

##############################################################################
# EKS cluster + managed node group (sized per environment)
##############################################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = true

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"
  }

  eks_managed_node_groups = {
    default = {
      instance_types = [local.cfg.node_type]
      min_size       = local.cfg.min_size
      desired_size   = local.cfg.desired_size
      max_size       = local.cfg.max_size

      labels = {
        environment = local.env
      }
    }
  }

  tags = local.tags
}

##############################################################################
# ECR — one repository per service (shared image registry, immutable tags)
##############################################################################
resource "aws_ecr_repository" "service" {
  for_each = toset(var.services)

  name                 = "${var.base_name}/${each.value}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "service" {
  for_each = aws_ecr_repository.service

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 20 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 20
        }
        action = { type = "expire" }
      }
    ]
  })
}
