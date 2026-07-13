# -----------------------------------------------------------------------------
# REMOTE STATE BACKEND CONFIGURATION
# -----------------------------------------------------------------------------
# Configures the storage of the OpenTofu state file in an AWS S3 bucket and
# concurrency locking via DynamoDB.
# -----------------------------------------------------------------------------
# NOTE: During initial bootstrapping, keep this block commented out so state
# is stored locally. After the S3 bucket and DynamoDB table are provisioned,
# uncomment this block and run:
#   tofu init -migrate-state
# -----------------------------------------------------------------------------

terraform {
  backend "s3" {
    bucket         = "homelab-babylon-tfstate"
    key            = "cloud/aws_global.tfstate"
    region         = "us-east-1"
    dynamodb_table = "homelab-babylon-tflocks"
    encrypt        = true
  }
}
