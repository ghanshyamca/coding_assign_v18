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
  description = "ECR repository URLs keyed by service name."
  value       = { for name, repo in aws_ecr_repository.service : name => repo.repository_url }
}

output "vpc_id" {
  description = "VPC id for this environment."
  value       = module.vpc.vpc_id
}
