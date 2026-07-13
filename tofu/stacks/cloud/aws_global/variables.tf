# -----------------------------------------------------------------------------
# AWS CONFIGURATION VARIABLES
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "The target AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
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
