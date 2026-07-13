# -----------------------------------------------------------------------------
# RESOURCE ORCHESTRATION - AWS GLOBAL RESOURCES
# -----------------------------------------------------------------------------
# This file dynamically creates S3 buckets, DynamoDB tables, and IAM users
# from data structures specified in tfvars files.
# -----------------------------------------------------------------------------

# ─── Step 1: Local Resources Parsing ──────────────────────────────────────────
locals {
  s3_buckets      = try(var.resources.s3_buckets, {})
  dynamodb_tables = try(var.resources.dynamodb_tables, {})
  iam_users       = try(var.resources.iam_users, {})
}

# ─── Step 2: S3 Bucket Orchestration ──────────────────────────────────────────
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

# Enable S3 Bucket Versioning dynamically where configured
resource "aws_s3_bucket_versioning" "versioning" {
  for_each = {
    for k, v in local.s3_buckets : k => v
    if try(v.versioning, false)
  }
  bucket = aws_s3_bucket.buckets[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

# Block all public access for security-first infrastructure
resource "aws_s3_bucket_public_access_block" "public_access" {
  for_each = local.s3_buckets
  bucket   = aws_s3_bucket.buckets[each.key].id

  block_public_acls       = try(each.value.block_public_access, true)
  block_public_policy     = try(each.value.block_public_access, true)
  ignore_public_acls      = try(each.value.block_public_access, true)
  restrict_public_buckets = try(each.value.block_public_access, true)
}

# ─── Step 3: DynamoDB Locking Tables Orchestration ────────────────────────────
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

# ─── Step 4: IAM Infrastructure (Access Control) ──────────────────────────────
resource "aws_iam_user" "users" {
  for_each = local.iam_users
  name     = each.value.username

  tags = {
    managed-by = "tofu"
    repo       = "https://github.com/sinhaaritro/platform-stack"
  }
}

# Policy attachment for programmatic access users
resource "aws_iam_user_policy_attachment" "user_policies" {
  for_each = {
    for k, v in local.iam_users : k => v
    if try(v.policy_arn, "") != ""
  }
  user       = aws_iam_user.users[each.key].name
  policy_arn = each.value.policy_arn
}

# ─── Step 5: Resource Outputs ─────────────────────────────────────────────────
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

output "iam_user_arn_map" {
  description = "A map of created IAM user ARNs keyed by their username."
  value = {
    for k, v in aws_iam_user.users : k => v.arn
  }
}
