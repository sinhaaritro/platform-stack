# -----------------------------------------------------------------------------
# REQUIRED PROVIDERS - CLOUDFLARE (ALEXANDRIA)
# -----------------------------------------------------------------------------
# Defines the OpenTofu providers required for the Cloudflare stack.
# -----------------------------------------------------------------------------

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# -----------------------------------------------------------------------------
# CLOUDFLARE PROVIDER CONFIGURATION
# -----------------------------------------------------------------------------
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
