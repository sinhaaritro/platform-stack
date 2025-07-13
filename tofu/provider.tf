# Block to define required providers like Proxmox
terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      version = "3.0.2-rc01"
    }
  }
}

# Block to configure the Proxmox provider with your credentials
provider "proxmox" {
  pm_api_url = var.proxmox_url
  pm_user    = var.proxmox_user
  pm_password = var.proxmox_password

  # This is critical for most home labs that use self-signed SSL certificates.
  # It tells Tofu to not fail if the certificate isn't from a trusted authority.
  pm_tls_insecure = true
}