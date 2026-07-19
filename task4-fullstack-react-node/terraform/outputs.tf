output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS Kubernetes API server."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate data required to communicate with the cluster."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "frontend_ecr_repository_url" {
  description = "URL of the frontend ECR repository."
  value       = module.ecr_frontend.repository_url
}

output "backend_ecr_repository_url" {
  description = "URL of the backend ECR repository."
  value       = module.ecr_backend.repository_url
}

output "region" {
  description = "AWS region the cluster is deployed in."
  value       = var.region
}

output "configure_kubectl" {
  description = "Command to configure kubectl for this cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
