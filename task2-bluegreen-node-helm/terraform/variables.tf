###############################################################################
# variables.tf
###############################################################################

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project / application base name. Used for tagging and naming."
  type        = string
  default     = "bluegreen-node"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "bluegreen-node-eks"
}

variable "cluster_version" {
  description = "Kubernetes control plane version for EKS."
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
  description = "Minimum number of worker nodes."
  type        = number
  default     = 2
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
}

variable "ecr_repo_name" {
  description = "Name of the ECR repository holding the app image."
  type        = string
  default     = "bluegreen-node"
}

variable "install_metrics_server" {
  description = "Whether to install the metrics-server helm release as part of the Helm setup."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags merged onto all resources."
  type        = map(string)
  default     = {}
}
