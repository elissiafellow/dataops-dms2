variable "private_subnet_ids" {
  description = "List of private subnet IDs where the EKS cluster will be deployed"
  type        = list(string)
}

variable "eks_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "eks_version" {
  description = "EKS version"
  type        = string
}

variable "env" {
  description = "Environment (e.g., production, staging)"
  type        = string
}

variable "eks_sg_id" {
  description = "ID of the extra security group for the EKS cluster"
  type        = string
}
