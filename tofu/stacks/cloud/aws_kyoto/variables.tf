# -----------------------------------------------------------------------------
# AWS CONFIGURATION VARIABLES
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "The target AWS region to deploy resources into."
  type        = string
}

# -----------------------------------------------------------------------------
# AWS AUTHENTICATION CREDENTIALS
# -----------------------------------------------------------------------------
variable "aws_credentials" {
  description = "AWS authentication credentials."
  sensitive   = true
  type = object({
    name       = string
    access_key = string
    secret_key = string
  })
}

# -----------------------------------------------------------------------------
# MAIN RESOURCE DEFINITION
# -----------------------------------------------------------------------------
# This maps the resource definitions for S3 buckets, DynamoDB, IAM users, etc.
# -----------------------------------------------------------------------------
variable "resources" {
  description = "A map of AWS resources definitions (S3 buckets, DynamoDB tables, IAM policies)."
  type        = any
  default     = {}
}

# -----------------------------------------------------------------------------
# DEBUG TOGGLE
# -----------------------------------------------------------------------------
variable "enable_debug" {
  description = "Controls whether debug info output is rendered."
  type        = bool
  default     = true
}
