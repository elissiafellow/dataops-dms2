terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Use local backend for demo (or change to S3 if needed)
  backend "local" {
    path = "terraform.tfstate"
  }
}

variable "aws_region" {
  description = "AWS region (should match demo-env/infra region)"
  type        = string
  default     = "eu-central-1"
}

provider "aws" {
  region = var.aws_region
}
