###############################################################################
# Task 5 - HA app on EKS with Auto Scaling (HPA + Cluster Autoscaler)
#
# This configuration provisions:
#   * A multi-AZ VPC (3 AZs) for high availability
#   * An EKS 1.33 cluster with IRSA/OIDC enabled
#   * A managed node group spanning 3 AZs (min 2 / desired 2 / max 6)
#   * An ECR repository (scan-on-push + lifecycle policy)
#   * metrics-server (required by HPA) via Helm
#   * cluster-autoscaler via Helm, wired to a dedicated IRSA role
###############################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  name    = var.project
  cluster = "${var.project}-eks"
  azs     = slice(data.aws_availability_zones.available.names, 0, 3)

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Task        = "task5-ha-autoscaling"
  }
}

###############################################################################
# Providers
###############################################################################

provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

# Authenticate the Helm and Kubernetes providers against the new cluster.
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

###############################################################################
# VPC - 3 AZs for multi-AZ high availability
###############################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k + 8)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags required so that the AWS Load Balancer / EKS can discover subnets.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                 = "1"
    "kubernetes.io/cluster/${local.cluster}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"        = "1"
    "kubernetes.io/cluster/${local.cluster}" = "shared"
  }

  tags = local.common_tags
}

###############################################################################
# EKS cluster + managed node group
###############################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster
  cluster_version = var.cluster_version

  # Public endpoint so CI (Jenkins) and operators can reach the API.
  cluster_endpoint_public_access = true

  # Enable IRSA / OIDC provider (required for the autoscaler service account).
  enable_irsa = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Grant the account running terraform admin access to the cluster.
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns                = {}
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
  }

  eks_managed_node_groups = {
    default = {
      name           = "${local.name}-ng"
      instance_types = var.node_instance_types

      min_size     = var.node_min_size
      desired_size = var.node_desired_size
      max_size     = var.node_max_size

      # Spread capacity across all 3 private subnets / AZs for HA.
      subnet_ids = module.vpc.private_subnets

      # Documentation tags on the node-group resource. Note: for EKS *managed*
      # node groups, AWS applies the k8s.io/cluster-autoscaler/* tags to the
      # underlying ASG automatically, which is what actually enables
      # autoDiscovery — these resource tags do not propagate to the ASG.
      tags = {
        "k8s.io/cluster-autoscaler/enabled"          = "true"
        "k8s.io/cluster-autoscaler/${local.cluster}" = "owned"
      }
    }
  }

  tags = local.common_tags
}

###############################################################################
# ECR repository for the app image
###############################################################################

resource "aws_ecr_repository" "app" {
  name                 = var.project
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 15 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 15
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

###############################################################################
# Cluster Autoscaler - IRSA role + Helm release
###############################################################################

# IAM role (assumable by the cluster-autoscaler service account via OIDC) with
# the managed cluster_autoscaler policy. This grants the autoscaler the
# autoscaling:DescribeAutoScalingGroups / SetDesiredCapacity /
# TerminateInstanceInAutoScalingGroup permissions it needs to scale nodes.
module "cluster_autoscaler_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name                        = "${local.name}-cluster-autoscaler"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [module.eks.cluster_name]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }

  tags = local.common_tags
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  namespace  = "kube-system"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = var.cluster_autoscaler_version

  # Auto-discover ASGs by the tags set on the node group above.
  set {
    name  = "autoDiscovery.clusterName"
    value = module.eks.cluster_name
  }

  # Pin the CA image to the cluster's Kubernetes minor — the chart's default
  # image lags behind and CA must match the control-plane minor version.
  set {
    name  = "image.tag"
    value = var.cluster_autoscaler_image_tag
  }

  set {
    name  = "awsRegion"
    value = var.region
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  # Wire the service account to the IRSA role created above.
  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.cluster_autoscaler_irsa.iam_role_arn
  }

  set {
    name  = "extraArgs.balance-similar-node-groups"
    value = "true"
  }

  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }

  depends_on = [module.eks]
}

###############################################################################
# metrics-server - required by the HorizontalPodAutoscaler
###############################################################################

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_version

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  depends_on = [module.eks]
}
