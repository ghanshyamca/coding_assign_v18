variable "repository_name" {
  description = "Name of the ECR repository."
  type        = string
}

variable "scan_on_push" {
  description = "Enable image vulnerability scanning on push."
  type        = bool
  default     = true
}

variable "image_tag_mutability" {
  description = "Tag mutability setting (MUTABLE or IMMUTABLE)."
  type        = string
  default     = "MUTABLE"
}

variable "keep_last_n_images" {
  description = "Number of most-recent images to retain via lifecycle policy."
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags to apply to the repository."
  type        = map(string)
  default     = {}
}
