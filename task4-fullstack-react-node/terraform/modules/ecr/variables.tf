variable "repository_name" {
  description = "Name of the ECR repository."
  type        = string
}

variable "image_tag_mutability" {
  description = "The tag mutability setting for the repository (MUTABLE or IMMUTABLE)."
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  description = "Whether images are scanned for vulnerabilities on push."
  type        = bool
  default     = true
}

variable "max_image_count" {
  description = "Maximum number of images to retain via the lifecycle policy."
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags to apply to the repository."
  type        = map(string)
  default     = {}
}
