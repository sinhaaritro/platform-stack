# -----------------------------------------------------------------------------
# STACK CONFIGURATION - AWS GLOBAL RESOURCES (Japanese Theme: `kyoto`)
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
      bucket_name         = "homelab-kyoto-tfstate"
      versioning          = true
      force_destroy       = false
      block_public_access = true
    }
    "backups" = {
      bucket_name         = "homelab-kyoto-backups-storage"
      versioning          = true
      force_destroy       = false
      block_public_access = true
    }
  }

  dynamodb_tables = {
    "tflocks" = {
      table_name   = "homelab-kyoto-tflocks"
      hash_key     = "LockID"
      billing_mode = "PAY_PER_REQUEST"
    }
  }

  # --- Managed IAM Groups ---
  iam_groups = {
    "backup-operators" = {
      group_name = "backup-operators"
    }
  }

  # --- Managed IAM Users ---
  iam_users = {
    "velero-backup" = {
      username = "sa-musashi"
      groups   = ["backup-operators"]
    }
  }

  # --- Managed Custom Policies ---
  iam_policies = {
    "velero-backup-policy" = {
      policy_name = "VeleroBackupPolicy"
      description = "Scoped S3 access for Velero backup/restore operations"
      policy_document = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "s3:GetObject",
              "s3:PutObject",
              "s3:DeleteObject",
              "s3:ListBucket",
              "s3:GetBucketLocation",
              "s3:ListMultipartUploadParts",
              "s3:AbortMultipartUpload"
            ]
            Resource = [
              "arn:aws:s3:::homelab-kyoto-backups-storage",
              "arn:aws:s3:::homelab-kyoto-backups-storage/*"
            ]
          }
        ]
      }
    }
  }

  # --- Managed Group Policy Attachments ---
  iam_group_policy_attachments = {
    "velero-attachment" = {
      group      = "backup-operators"
      policy_key = "velero-backup-policy"
    }
  }
}
