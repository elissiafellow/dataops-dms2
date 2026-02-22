variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
}

variable "public_subnets" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
}

variable "private_subnets" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
}

variable "outpost_private_subnets" {
  description = "outpost Private subnet CIDR blocks"
  type        = list(string)
}

variable "azs" {
  description = "Availability Zones"
  type        = list(string)
}

variable "env" {
  description = "Environment (e.g., production, staging)"
  type        = string
}

variable "eks_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "eks_version" {
  description = "EKS version"
  type        = string
}

variable "bastion_ami" {
  description = "AMI ID for the Bastion host"
  type        = string
}

variable "bastion_key_name" {
  description = "Key pair name for the Bastion host"
  type        = string
}

variable "allowed_ips" {
  description = "CIDR blocks allowed to access the Bastion host"
  type        = list(string)
}

# variable "rds_vpc_cidr" {
#   description = "VPC CIDR of the source DB"
#   type = string
# }

# variable "rds_vpc_id" {
#   description = "VPC ID of the source DB"
#   type = string
# }

# variable "rds_route_table_id" {
#   description = "VPC ROUTE TABLE ID of the source DB"
#   type = string
# }