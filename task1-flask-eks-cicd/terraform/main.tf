###############################################################################
# Providers, data sources and common locals
###############################################################################
provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # First N AZs in the region.
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Common tags applied to every resource.
  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Application = "flask-eks"
  }

  # Non-overlapping /20 subnets carved out of the VPC CIDR.
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 8)]
}

###############################################################################
# VPC (official terraform-aws-modules/vpc)
###############################################################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  # Single shared NAT gateway to keep costs low for the demo.
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Subnet tags required by the AWS Load Balancer Controller / EKS so that
  # public subnets host internet-facing ELBs and private subnets host internal.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = local.tags
}

###############################################################################
# EKS cluster (official terraform-aws-modules/eks) with managed node group
###############################################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Endpoint reachable both publicly and from within the VPC.
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # IRSA: create an OIDC provider so pods can assume IAM roles.
  enable_irsa = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Grant the identity running terraform admin access to the cluster.
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"
  }

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]

      min_size     = var.node_min_size
      desired_size = var.node_desired_size
      max_size     = var.node_max_size

      capacity_type = "ON_DEMAND"

      labels = {
        role = "general"
      }
    }
  }

  tags = local.tags
}

###############################################################################
# ECR repository (thin local module)
###############################################################################
module "ecr" {
  source = "./modules/ecr"

  repository_name      = var.project
  scan_on_push         = true
  image_tag_mutability = "MUTABLE"
  keep_last_n_images   = 10

  tags = local.tags
}
