# -----------------------------------------------------------------------------
# STACK CONFIGURATION - NETBIRD MESH OVERLAY (Codename: `samarkand`)
# -----------------------------------------------------------------------------

netbird_api_url = "https://api.netbird.io"
enable_debug    = true

netbird = {
  # Groups to establish in Netbird
  groups = {
    "servers" = {
      name = "servers"
    }
    "proxmox-atlas" = {
      name = "proxmox-atlas"
    }
    "k8s-nodes" = {
      name = "k8s-nodes"
    }
  }

  # Setup Keys for onboarding nodes (e.g. Proxmox Atlas containers/VMs)
  setup_keys = {
    "atlas_onboarding" = {
      name               = "Proxmox Atlas Onboarding Key"
      type               = "reusable"
      expires_in         = 7776000 # 90 days
      auto_assign_groups = ["servers", "proxmox-atlas"]
      usage_limit        = 0
      ephemeral          = false
    }
  }
}
