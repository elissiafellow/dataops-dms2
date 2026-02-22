variable "aws_region" {
  type        = string
  default     = "eu-central-1"
  description = "AWS region to create resources in."
}

variable "repository_name" {
  type        = string
  default     = "kafka-connect-cluster"
  description = "Name of the ECR repository."
}

variable "image_name" {
  type        = string
  default     = "kafka-connect-cluster"
  description = "Local tag used when building the Docker image."
}
