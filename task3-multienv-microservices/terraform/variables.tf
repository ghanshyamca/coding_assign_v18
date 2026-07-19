variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "base_name" {
  description = "Base name used across all resources."
  type        = string
  default     = "microsvc"
}

variable "kubernetes_version" {
  description = "EKS control plane Kubernetes version."
  type        = string
  default     = "1.30"
}

variable "services" {
  description = "List of microservices that get an ECR repository each."
  type        = list(string)
  default     = ["api-gateway", "orders"]
}
