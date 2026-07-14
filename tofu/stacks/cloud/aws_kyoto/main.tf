# -----------------------------------------------------------------------------
# RESOURCE ORCHESTRATION - AWS GLOBAL RESOURCES (Japanese Theme: `kyoto`)
# -----------------------------------------------------------------------------
# This file dynamically creates S3 buckets, DynamoDB tables, and IAM resources
# from data structures specified in tfvars files.
# -----------------------------------------------------------------------------

# ─── 1. S3 Buckets ──────────────────────────────────────────────────────────
locals {
  s3_buckets = try(var.resources.s3_buckets, {})
}

resource "aws_s3_bucket" "buckets" {
  for_each      = local.s3_buckets
  bucket        = each.value.bucket_name
  force_destroy = try(each.value.force_destroy, false)
  tags = {
    Name       = each.value.bucket_name
    managed-by = "tofu"
    repo       = "https://github.com/sinhaaritro/platform-stack"
  }
}

resource "aws_s3_bucket_versioning" "versioning" {
  for_each = {
    for k, v in local.s3_buckets : k => v if try(v.versioning, false)
  }
  bucket = aws_s3_bucket.buckets[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  for_each = local.s3_buckets
  bucket   = aws_s3_bucket.buckets[each.key].id
  block_public_acls       = try(each.value.block_public_access, true)
  block_public_policy     = try(each.value.block_public_access, true)
  ignore_public_acls      = try(each.value.block_public_access, true)
  restrict_public_buckets = try(each.value.block_public_access, true)
}

resource "aws_s3_bucket_lifecycle_configuration" "lifecycles" {
  for_each = {
    for k, v in local.s3_buckets : k => v if try(v.noncurrent_version_expiration_days, 0) > 0
  }

  bucket = aws_s3_bucket.buckets[each.key].id

  rule {
    id     = "cleanup-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = each.value.noncurrent_version_expiration_days
    }
  }
}

# ─── 2. DynamoDB Tables ──────────────────────────────────────────────────────
locals {
  dynamodb_tables = try(var.resources.dynamodb_tables, {})
}

resource "aws_dynamodb_table" "tables" {
  for_each     = local.dynamodb_tables
  name         = each.value.table_name
  billing_mode = try(each.value.billing_mode, "PAY_PER_REQUEST")
  hash_key     = try(each.value.hash_key, "LockID")
  attribute {
    name = try(each.value.hash_key, "LockID")
    type = "S"
  }
  tags = {
    Name       = each.value.table_name
    managed-by = "tofu"
    repo       = "https://github.com/sinhaaritro/platform-stack"
  }
}

# ─── 3. IAM Custom Policies ──────────────────────────────────────────────────
locals {
  iam_policies = try(var.resources.iam_policies, {})
}

resource "aws_iam_policy" "policies" {
  for_each    = local.iam_policies
  name        = each.value.policy_name
  description = try(each.value.description, "")
  policy      = jsonencode(each.value.policy_document)
}

# ─── 4. IAM Groups ───────────────────────────────────────────────────────────
locals {
  iam_groups = try(var.resources.iam_groups, {})
}

resource "aws_iam_group" "groups" {
  for_each = local.iam_groups
  name     = each.value.group_name
}

# Attach custom policies to IAM groups
locals {
  iam_group_policy_attachments = try(var.resources.iam_group_policy_attachments, {})
}

resource "aws_iam_group_policy_attachment" "group_policy_attachments" {
  for_each   = local.iam_group_policy_attachments
  group      = aws_iam_group.groups[each.value.group].name
  policy_arn = aws_iam_policy.policies[each.value.policy_key].arn
}

# ─── 5. IAM Users & Memberships ──────────────────────────────────────────────
locals {
  iam_users = try(var.resources.iam_users, {})
}

resource "aws_iam_user" "users" {
  for_each = local.iam_users
  name     = each.value.username
  tags = {
    managed-by = "tofu"
    repo       = "https://github.com/sinhaaritro/platform-stack"
  }
}

# Add users to their respective groups
locals {
  # Build a flattened list of user-to-group associations
  user_group_pair = flatten([
    for user_key, user in local.iam_users : [
      for group in try(user.groups, []) : {
        user_key = user_key
        user     = user.username
        group    = group
      }
    ]
  ])
  user_group_map = {
    for pair in local.user_group_pair : "${pair.user}-${pair.group}" => pair
  }
}

resource "aws_iam_user_group_membership" "user_memberships" {
  for_each = local.user_group_map
  user     = aws_iam_user.users[each.value.user_key].name
  groups   = [aws_iam_group.groups[each.value.group].name]
}

# ─── 6. Resource Outputs ─────────────────────────────────────────────────────
output "s3_bucket_arn_map" {
  description = "A map of created S3 bucket ARNs keyed by their identifier."
  value = {
    for k, v in aws_s3_bucket.buckets : k => v.arn
  }
}

output "dynamodb_table_arn_map" {
  description = "A map of created DynamoDB table ARNs keyed by their identifier."
  value = {
    for k, v in aws_dynamodb_table.tables : k => v.arn
  }
}

output "iam_group_arn_map" {
  description = "A map of created IAM group ARNs keyed by their identifier."
  value = {
    for k, v in aws_iam_group.groups : k => v.arn
  }
}

output "iam_policy_arn_map" {
  description = "A map of created IAM policy ARNs keyed by their identifier."
  value = {
    for k, v in aws_iam_policy.policies : k => v.arn
  }
}

output "iam_user_arn_map" {
  description = "A map of created IAM user ARNs keyed by their identifier."
  value = {
    for k, v in aws_iam_user.users : k => v.arn
  }
}

# ─── VELERO DYNAMIC ACCESS KEY & OUTPUTS ────────────────────────────────────
resource "aws_iam_access_key" "velero" {
  user = aws_iam_user.users["velero-backup"].name
}

resource "local_file" "aws_secrets" {
  filename = "${path.module}/../../../../ansible/inventory.d/aws_kyoto.yml"
  content  = <<EOT
# Generated by OpenTofu - aws_kyoto stack
# Do not edit manually

all:
  vars:
    aws_velero_access_key_id: "${aws_iam_access_key.velero.id}"
    aws_velero_secret_access_key: "${aws_iam_access_key.velero.secret}"
EOT
}

output "velero_access_key_id" {
  description = "The generated AWS Access Key ID for Velero."
  value       = aws_iam_access_key.velero.id
  sensitive   = true
}

output "velero_secret_access_key" {
  description = "The generated AWS Secret Access Key for Velero."
  value       = aws_iam_access_key.velero.secret
  sensitive   = true
}
