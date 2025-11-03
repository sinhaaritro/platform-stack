# -----------------------------------------------------------------------------
# REQUIRED PROVIDERS
# -----------------------------------------------------------------------------
# Defines the OpenTofu providers required for this stack and pins their versions
# to ensure consistent and predictable behavior.
# -----------------------------------------------------------------------------

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.85.1"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.4"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.5.3"
    }
  }
}

# -----------------------------------------------------------------------------
# PROMOX PROVIDER CONFIGURATION
# -----------------------------------------------------------------------------
# Configures the connection to the Proxmox server. It dynamically sets the
# authentication parameters based on the 'auth_method' defined in the
# proxmox_connection variable.
# -----------------------------------------------------------------------------

provider "proxmox" {
  endpoint = var.proxmox_connection.url
  insecure = var.proxmox_connection.insecure_tls

  # --- Dynamic Authentication ---
  # Ternary operators are used to set the appropriate auth values to null if
  # the method is not selected, which Terraform then ignores.

  # 1. API Token Authentication
  api_token = (
    var.proxmox_connection.auth_method == "token"
    ? format("%s=%s", var.proxmox_connection.token_auth.id, var.proxmox_connection.token_auth.secret)
    : null
  )

  # 2. Username and Password Authentication
  username = (
    var.proxmox_connection.auth_method == "password"
    ? var.proxmox_connection.password_auth.user
    : null
  )
  password = (
    var.proxmox_connection.auth_method == "password"
    ? var.proxmox_connection.password_auth.password
    : null
  )

  # 3. Ticket-based Authentication
  auth_ticket = (
    var.proxmox_connection.auth_method == "ticket"
    ? var.proxmox_connection.ticket_auth.auth_ticket
    : null
  )
  csrf_prevention_token = (
    var.proxmox_connection.auth_method == "ticket"
    ? var.proxmox_connection.ticket_auth.csrf_prevention_token
    : null
  )
}
