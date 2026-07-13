# -----------------------------------------------------------------------------
# STACK CONFIGURATION - AWS GLOBAL RESOURCES
# -----------------------------------------------------------------------------
# Non-sensitive configuration file defining S3, DynamoDB, and IAM resources.
# -----------------------------------------------------------------------------

aws_region   = "us-east-1"
enable_debug = true

# Resource Definitions
# Defines the map of resources to be managed in this AWS account.
resources = {
  s3_buckets = {
    "tfstate" = {
      bucket_name         = "homelab-babylon-tfstate"
      versioning          = true
      force_destroy       = false
      block_public_access = true
    }
    "backups" = {
      bucket_name         = "homelab-babylon-backups-storage"
      versioning          = true
      force_destroy       = false
      block_public_access = true
    }
  }

  dynamodb_tables = {
    "tflocks" = {
      table_name   = "homelab-babylon-tflocks"
      hash_key     = "LockID"
      billing_mode = "PAY_PER_REQUEST"
    }
  }

  iam_users = {
    "backup-runner" = {
      username   = "sa-backup-runner"
      policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess" # Can be tightened to a custom policy later
    }
  }
}
