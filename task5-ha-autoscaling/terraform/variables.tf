variable "region" {
  description = "AWS region to deploy the EKS cluster into."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Base name used to prefix and tag all resources."
  type        = string
  default     = "ha-app"
}

variable "environment" {
  description = "Deployment environment name (dev/stage/prod)."
  type        = string
  default     = "dev"
}

variable "cluster_version" {
  description = "Kubernetes control-plane version for EKS."
  type        = string
  default     = "1.33"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  description = "Minimum number of worker nodes (floor for Cluster Autoscaler)."
  type        = number
  default     = 2
}

variable "node_desired_size" {
  description = "Initial desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes (ceiling for Cluster Autoscaler)."
  type        = number
  default     = 6
}

variable "metrics_server_version" {
  description = "Helm chart version for metrics-server."
  type        = string
  default     = "3.12.1"
}

variable "cluster_autoscaler_image_tag" {
  description = "Cluster Autoscaler image tag — keep the minor in sync with cluster_version."
  type        = string
  default     = "v1.33.0"
}

variable "cluster_autoscaler_version" {
  description = "Helm chart version for cluster-autoscaler."
  type        = string
  default     = "9.37.0"
}
