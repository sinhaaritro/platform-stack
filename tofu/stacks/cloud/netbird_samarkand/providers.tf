# -----------------------------------------------------------------------------
# REQUIRED PROVIDERS - NETBIRD (SAMARKAND)
# -----------------------------------------------------------------------------
# Defines the OpenTofu providers required for the Netbird stack.
# -----------------------------------------------------------------------------

terraform {
  required_providers {
    netbird = {
      source  = "netbirdio/netbird"
      version = "~> 0.0.9"
    }
  }
}

# -----------------------------------------------------------------------------
# NETBIRD PROVIDER CONFIGURATION
# -----------------------------------------------------------------------------
provider "netbird" {
  token = var.netbird_management_token
  url   = var.netbird_api_url
}
