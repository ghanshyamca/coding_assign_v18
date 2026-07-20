###############################################################################
# main.tf
# Provisions: VPC -> EKS (managed node group, IRSA/OIDC) -> ECR, and wires the
# kubernetes + helm providers to the freshly created cluster. Optionally
# installs a metrics-server helm release to demonstrate the "Helm setup".
###############################################################################

#######################################
# Common tags / locals
#######################################
locals {
  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "task2-bluegreen-node-helm"
    },
    var.tags,
  )

  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

data "aws_availability_zones" "available" {
  state = "available"
}

#######################################
# VPC
#######################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k + 8)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags required so the AWS cloud provider / LB controller can discover subnets.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = local.common_tags
}

#######################################
# EKS cluster + managed node group (IRSA / OIDC enabled)
#######################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Public endpoint so Jenkins / kubectl can reach the API. Lock this down
  # to your CI/CD egress CIDRs in production.
  cluster_endpoint_public_access = true

  # Enables IRSA (IAM Roles for Service Accounts) via the OIDC provider.
  enable_irsa = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Grant the identity running terraform admin access on the cluster.
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {}
    eks-pod-identity-agent = {}
  }

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      min_size       = var.node_min_size
      desired_size   = var.node_desired_size
      max_size       = var.node_max_size
      capacity_type  = "ON_DEMAND"

      labels = {
        role = "general"
      }
    }
  }

  tags = local.common_tags
}

#######################################
# ECR repository for the app image
#######################################
resource "aws_ecr_repository" "app" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}

# Keep only the last 10 images to control storage cost.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

#######################################
# Provider wiring to the created cluster
#
# Uses the EKS module's own outputs plus the aws-cli exec plugin (fresh token
# on every call) instead of data sources — data lookups resolve at plan time
# and fail on a fresh apply when the cluster doesn't exist yet.
#######################################
provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}

#######################################
# Helm setup example (part of "Terraform for EKS + Helm setup")
#
# metrics-server is installed as a demonstration of provisioning cluster
# add-ons through Terraform's helm_release. For blue-green routing at the edge
# you would additionally install ingress-nginx or the AWS Load Balancer
# Controller here (example block left commented below).
#######################################
resource "helm_release" "metrics_server" {
  count = var.install_metrics_server ? 1 : 0

  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.1"
  namespace  = "kube-system"

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  depends_on = [module.eks]
}

# ---------------------------------------------------------------------------
# Example: ingress-nginx as the public entrypoint for blue-green traffic.
# Uncomment to expose the "-active" production Service through an ingress.
#
# resource "helm_release" "ingress_nginx" {
#   name             = "ingress-nginx"
#   repository       = "https://kubernetes.github.io/ingress-nginx"
#   chart            = "ingress-nginx"
#   version          = "4.11.2"
#   namespace        = "ingress-nginx"
#   create_namespace = true
#
#   set {
#     name  = "controller.service.type"
#     value = "LoadBalancer"
#   }
#
#   depends_on = [module.eks]
# }
# ---------------------------------------------------------------------------
