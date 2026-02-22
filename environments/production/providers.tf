
terraform {
  required_version = ">= 1.9.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.82.2"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.5.2"  # Use the appropriate version
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.0.0"
    }
  }
  
    backend "s3" {
    bucket         	   =  "moneyfellows-prod-dms-statefiles"
    key              	   = "state/dev/resource.tfstate"
    region         	   = "eu-central-1"
    encrypt        	   = true
    kms_key_id         = "arn:aws:kms:eu-central-1:528757825065:key/5fd012ab-f41e-4057-8cfe-1976ae474701"
    # dynamodb_table         = "terraform_state_lock"
  }
}

# Define the default provider for your account
provider "aws" {
  alias   = "dataops-account"
  region  = var.region
  # profile = "dataops-account" # Replace with your AWS CLI profile name for your account
}

# # Define the provider for the RDS account
# provider "aws" {
#   alias   = "rds_account"
#   region  = var.region
#   profile = "rds-account" # Replace with your AWS CLI profile name for the RDS account
# }

# Use the DataOps provider
data "aws_caller_identity" "dataops" {
  provider = aws.dataops-account
}

# # Use the RDS provider
# data "aws_caller_identity" "rds" {
#   provider = aws.rds_account
# }
