# -----------------------------------------------------------------------------
# REQUIRED PROVIDERS
# -----------------------------------------------------------------------------
# Defines the OpenTofu providers required for this module and pins their 
# versions to ensure consistent and predictable behavior.
# -----------------------------------------------------------------------------

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.85.1"
    }
  }
}
