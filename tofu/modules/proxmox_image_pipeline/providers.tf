# -----------------------------------------------------------------------------
# REQUIRED PROVIDERS
# -----------------------------------------------------------------------------
# Defines the required providers and versions for the image pipeline module.
# -----------------------------------------------------------------------------

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.1"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.4"
    }
  }
}
