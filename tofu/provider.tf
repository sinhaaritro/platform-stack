# -----------------------------------------------------------------------------
# PROVIDER CONFIGURATION
#
# This file defines the Proxmox provider and configures its connection
# parameters using the variables defined in variables.tf. It also includes
# the critical Workspace Guardrail precondition check.
# -----------------------------------------------------------------------------

# --- Define Required Provider ---
# Specifies the source and version of the Proxmox provider we are using.
terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc04"
    }

    # Needed for file output
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}


# --- Configure Proxmox Provider ---
# This block sets up the connection to the Proxmox API.
provider "proxmox" {
  # --- Standard Connection Details ---
  pm_api_url      = var.proxmox_connection.url

  # This is critical for most home labs that use self-signed SSL certificates.
  # It tells Tofu to not fail if the certificate isn't from a trusted authority.
  pm_tls_insecure = var.proxmox_connection.insecure_tls

  # --- Conditional Authentication ---
  # These arguments use conditional logic to set the correct authentication
  # parameters based on the 'auth_method' defined in the .tfvars file.
  # If the condition is false, the argument is set to 'null' and is ignored by OpenTofu.

  # Set user/password only if auth_method is 'password'
  pm_user         = var.proxmox_connection.auth_method == "password" ? var.proxmox_connection.password_auth.user : null
  pm_password     = var.proxmox_connection.auth_method == "password" ? var.proxmox_connection.password_auth.password : null

  # Set API token ID/secret only if auth_method is 'token'
  pm_api_token_id     = var.proxmox_connection.auth_method == "token" ? var.proxmox_connection.token_auth.id : null
  pm_api_token_secret = var.proxmox_connection.auth_method == "token" ? var.proxmox_connection.token_auth.secret : null
}