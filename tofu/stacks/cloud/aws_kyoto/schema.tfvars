# -----------------------------------------------------------------------------
# STACK CONFIGURATION - AWS GLOBAL RESOURCES (Japanese Theme: `kyoto`)
# -----------------------------------------------------------------------------
# Non-sensitive configuration file defining resources.
# -----------------------------------------------------------------------------

aws_region   = "ap-southeast-1" # Singapore Region
enable_debug = true

# Resource Definitions
# Defines the map of resources to be managed in this AWS account.
resources = {
  s3_buckets = {
    "backups" = {
      bucket_name                        = "hyperion-velero-backups"
      versioning                         = true
      force_destroy                      = false
      block_public_access                = true
      noncurrent_version_expiration_days = 14
    }
    "immich" = {
      bucket_name                        = "hyperion-immich-file"
      versioning                         = true
      force_destroy                      = false
      block_public_access                = true
      noncurrent_version_expiration_days = 14
    }
    # "homelab" = {
    #   bucket_name                        = "aritro-homelab"
    #   versioning                         = true
    #   force_destroy                      = false
    #   block_public_access                = true
    #   noncurrent_version_expiration_days = 14
    # }
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
              "arn:aws:s3:::hyperion-velero-backups",
              "arn:aws:s3:::hyperion-velero-backups/*",
              "arn:aws:s3:::hyperion-immich-file",
              "arn:aws:s3:::hyperion-immich-file/*"
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
