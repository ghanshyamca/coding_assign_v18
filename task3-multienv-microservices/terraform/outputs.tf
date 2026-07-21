output "environment" {
  description = "Active terraform workspace / environment."
  value       = terraform.workspace
}

output "cluster_name" {
  description = "EKS cluster name for this environment."
  value       = local.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_region" {
  description = "Region the cluster runs in."
  value       = var.aws_region
}

output "kubeconfig_command" {
  description = "Run this to configure kubectl for the environment."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${local.cluster_name}"
}

output "ecr_repository_urls" {
  description = "ECR repository URLs keyed by service name (same registry for every workspace; repos are owned by the dev workspace)."
  value = {
    for s in var.services :
    s => "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.base_name}/${s}"
  }
}

output "vpc_id" {
  description = "VPC id for this environment."
  value       = module.vpc.vpc_id
}
