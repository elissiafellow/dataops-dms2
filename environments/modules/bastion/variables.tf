variable "ami" {
  description = "AMI ID for the bastion host"
  type        = string
}

variable "vpc_id" {
  description = "The VPC ID where the bastion host will be deployed"
  type        = string
}

variable "vpc_name" {
  description = "The name of the VPC"
  type        = string
}

variable "public_subnet_id" {
  description = "The public subnet ID where the bastion host will be deployed"
  type        = string
}

variable "allowed_ips" {
  description = "List of IPs allowed to access the bastion host via SSH"
  type        = list(string)
}

variable "key_name" {
  description = "Key pair name for SSH access to the bastion host"
  type        = string
}

variable "env" {
  description = "Environment (e.g., production, staging)"
  type        = string
}

variable "ssh_pem_bucket" {
  description = "s3 bucket to upload the bastion host ssh pem"
  type        = string
}

variable "instance_profile_name"{
  description = "the instance profile name that has the premissions required by the bastion host"
  type = string
}