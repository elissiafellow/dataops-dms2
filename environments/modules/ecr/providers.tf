terraform {
  required_version = ">= 1.9.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.82.2"
      configuration_aliases = [
        aws
      ]
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0.0"
    }
  }
}