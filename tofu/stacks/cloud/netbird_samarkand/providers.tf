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
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# -----------------------------------------------------------------------------
# NETBIRD PROVIDER CONFIGURATION
# -----------------------------------------------------------------------------
provider "netbird" {
  token          = var.netbird_management_token
  management_url = var.netbird_api_url
}
