# -----------------------------------------------------------------------------
# STACK CONFIGURATION - NETBIRD MESH OVERLAY (Codename: `samarkand`)
# -----------------------------------------------------------------------------

netbird_api_url = "https://api.netbird.io"
enable_debug    = true

netbird = {
  # -----------------------------------------------------------------
  # GROUPS (peer segmentation aligned to architecture zones)
  # -----------------------------------------------------------------
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
    "gateway-routers" = {
      name = "gateway-routers"
    }
    "admin-devices" = {
      name = "admin-devices"
    }
    "vps-bridges" = {
      name = "vps-bridges"
    }
  }

  # -----------------------------------------------------------------
  # SETUP KEYS (enrollment per architecture zone)
  # -----------------------------------------------------------------
  setup_keys = {
    "atlas_onboarding" = {
      name           = "Proxmox Atlas Onboarding Key"
      type           = "reusable"
      expiry_seconds = 7776000 # 90 days
      auto_groups    = ["servers", "proxmox-atlas"]
      usage_limit    = 0
      ephemeral      = false
    }
    "k8s_worker_onboarding" = {
      name           = "K8s Worker Node Key"
      type           = "reusable"
      expiry_seconds = 7776000
      auto_groups    = ["servers", "k8s-nodes"]
      usage_limit    = 0
      ephemeral      = false
    }
    "vps_bridge_onboarding" = {
      name           = "VPS Bridge Node Key (Zone 2)"
      type           = "reusable"
      expiry_seconds = 7776000
      auto_groups    = ["vps-bridges"]
      usage_limit    = 2
      ephemeral      = false
    }
  }

  # -----------------------------------------------------------------
  # ROUTES (Zone 3: Subnet routing to homelab LAN)
  # -----------------------------------------------------------------
  routes = {
    "homelab-subnet" = {
      description           = "Route homelab LAN 192.168.0.0/24 via gateway"
      network_id            = "homelab-lan"
      network               = "192.168.0.0/24"
      peer_id               = null # Fill after gateway peer enrollment
      peer_groups           = ["servers", "gateway-routers"]
      groups                = ["admin-devices"]
      access_control_groups = ["admin-devices"]
      masquerade            = true
      metric                = 9999
    }
  }

  # -----------------------------------------------------------------
  # POLICIES (access control per architecture zone)
  # -----------------------------------------------------------------
  policies = {
    "admin-full-access" = {
      name        = "Admin Full Mesh Access"
      description = "Zone 3: Admin devices can reach all servers"
      enabled     = true
      rules = [
        {
          name          = "admin-to-servers"
          action        = "accept"
          bidirectional = true
          protocol      = "all"
          sources       = ["admin-devices"]
          destinations  = ["servers"]
        }
      ]
    }
    "server-to-server" = {
      name        = "Server Internal Communication"
      description = "All servers can communicate with each other"
      enabled     = true
      rules = [
        {
          name          = "inter-server"
          action        = "accept"
          bidirectional = true
          protocol      = "all"
          sources       = ["servers"]
          destinations  = ["servers"]
        }
      ]
    }
    "vps-to-servers" = {
      name        = "VPS Bridge to Servers"
      description = "Zone 2: VPS bridges can reach servers for reverse proxy"
      enabled     = true
      rules = [
        {
          name          = "vps-media-access"
          action        = "accept"
          bidirectional = true
          protocol      = "tcp"
          sources       = ["vps-bridges"]
          destinations  = ["servers"]
          ports         = ["8096", "8920"]
        }
      ]
    }
    "ssh-access" = {
      name        = "NetBird SSH Access"
      description = "Zone 4: Enable NetBird embedded SSH for WASM browser access"
      enabled     = true
      rules = [
        {
          name          = "ssh-admin-to-servers"
          action        = "accept"
          bidirectional = true
          protocol      = "netbird-ssh"
          sources       = ["admin-devices"]
          destinations  = ["servers"]
        }
      ]
    }
  }

  # -----------------------------------------------------------------
  # NAMESERVER GROUPS (optional — uncomment to enable)
  # -----------------------------------------------------------------
  # nameserver_groups = {
  #   "homelab-dns" = {
  #     name        = "Homelab DNS"
  #     description = "Forward DNS for homelab domain via internal resolver"
  #     nameservers = [
  #       {
  #         ip      = "192.168.1.1"
  #         ns_type = "udp"
  #         port    = 53
  #       }
  #     ]
  #     groups                 = ["servers", "admin-devices"]
  #     domains                = ["home.arpa", "strawslabs.local"]
  #     search_domains_enabled = true
  #     primary                = false
  #   }
  # }
}
