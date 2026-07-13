# -----------------------------------------------------------------------------
# REQUIRED PROVIDERS
# -----------------------------------------------------------------------------
# Defines the OpenTofu providers required for the AWS stack and pins versions.
# -----------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.5.3"
    }
  }
}

# -----------------------------------------------------------------------------
# AWS PROVIDER CONFIGURATION
# -----------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region
}
