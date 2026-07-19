output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS Kubernetes API server."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "ecr_url" {
  description = "URL of the ECR repository for the app image."
  value       = aws_ecr_repository.app.repository_url
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN assumed by the cluster-autoscaler service account."
  value       = module.cluster_autoscaler_irsa.iam_role_arn
}

output "region" {
  description = "AWS region the cluster is deployed in."
  value       = var.region
}

output "kubectl_config_command" {
  description = "Command to update your kubeconfig to talk to the cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
