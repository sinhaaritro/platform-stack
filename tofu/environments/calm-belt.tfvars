# -----------------------------------------------------------------------------
# ENVIRONMENT: Calm Belt (Sandbox)
#
# This file contains all the specific data needed to provision the
# Calm Belt (sandbox) environment.
#
# USAGE:
# 1. Ensure you are in the 'calm-belt' workspace: `tofu workspace select calm-belt`
# 2. Run commands with this file: `tofu plan -var-file="environments/calm-belt.tfvars"`
# -----------------------------------------------------------------------------


# --- Workspace Guardrail ---
# This value MUST match the OpenTofu workspace name for this environment.
# It is a critical safety feature to prevent cross-environment changes.

environment_name = "calm-belt"

# --- Proxmox Connection ---
# Defines the API endpoint and credentials for the Calm Belt Proxmox server.
# IMPORTANT: Replace these values with your actual sandbox credentials.

proxmox_connection = {
  url          = "https://192.168.0.2:8006/api2/json"
  insecure_tls = true
  auth_method  = "password"
  password_auth = {
    user     = "vmprovisioner@pve"
    password = "vmprovisioner"
  }
}


# --- Default User Configuration ---
# Defines the non-secret user information.
user_profile = {
  username        = "dev"
  package_upgrade = true
}

# Defines the secret user information.
user_credentials = {
  password        = "dev"
  ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDwC01G8nJScuxp7Cga8uUsnHUW2IpXXiiTw1gzhEL4P RyzenWindows"]
}


# -----------------------------------------------------------------------------
# MASTER RESOURCE DEFINITIONS
#
# This is the primary declaration of all infrastructure for this environment.
# Each top-level key (e.g., "laboon_cluster") represents a group of
# resources that are managed together.
# -----------------------------------------------------------------------------

resource_groups = {

  # --- Laboon Cluster ---
  "laboon_cluster" = {
    enabled              = true
    type                 = "qemu"
    template             = "ubuntu-cloud-init"
    hardware_profile_key = "small"
    tags                 = ["cluster", "laboon", "kubernetes-worker"]

    nodes = {
      "laboon-1" = { id = 1002, ip = "192.168.0.4" },
      "laboon-2" = { id = 1003, ip = "192.168.0.5" },
      "laboon-3" = { id = 1004, ip = "192.168.0.6" },
    }
  },


  # --- Lord of the Coast Cluster ---
  "lord_of_the_coast_cluster" = {
    enabled              = false
    type                 = "qemu"
    template             = "ubuntu-cloud-init"
    hardware_profile_key = "small"
    tags                 = ["cluster", "lord-of-the-coast", "testing"]

    nodes = {
      "lord-of-the-coast-1" = { id = 1005, ip = "192.168.0.7" },
      "lord-of-the-coast-2" = { id = 1006, ip = "192.168.0.8" },
      "lord-of-the-coast-3" = { id = 1007, ip = "192.168.0.9" },
    }
  },

  # --- Lord of the Coast Cluster ---
  "kung_fu_dugong_cluster" = {
    enabled              = false
    type                 = "qemu"
    template             = "ubuntu-cloud-init"
    hardware_profile_key = "small"
    tags                 = ["cluster", "kung-fu-dugong", "testing"]

    nodes = {
      "kung-fu-dugong-1" = { id = 1008, ip = "192.168.0.10" },
      "kung-fu-dugong-2" = { id = 1009, ip = "192.168.0.11" },
      "kung-fu-dugong-3" = { id = 1010, ip = "192.168.0.12" },
    }
  },

  # --- Standalone Web Server ---
  "yuda_server" = {
    enabled              = true
    type                 = "qemu"
    template             = "ubuntu-cloud-init"
    hardware_profile_key = "medium"
    tags                 = ["standalone", "yuda_server"]

    nodes = {
      "yuda" = { id = 1011, ip = "192.168.0.13" },
    }
  }

  "megalo_server" = {
    enabled              = true
    type                 = "qemu"
    template             = "ubuntu-cloud-init"
    hardware_profile_key = "medium"
    tags                 = ["standalone", "megalo_server", "docker"]

    nodes = {
      "megalo" = { id = 1012, ip = "192.168.0.14" },
    }
  }


  # --- Standalone Web Server ---
  # "web_server" = {
  #   enabled               = false
  #   type                  = "lxc"
  #   template              = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
  #   hardware_profile_key  = "small"
  #   tags                  = ["standalone", "webserver", "apache"]

  #   nodes = {
  #     "web-01" = { id = 2001, ip = "192.168.0.100" },
  #   }
  # }

}

# -----------------------------------------------------------------------------
# ENVIRONMENT-SPECIFIC DEFAULTS
#
# Overriding the global defaults to match the specific configuration
# of the 'calm-belt' Proxmox installation. This is critical for preventing
# placement errors.
# -----------------------------------------------------------------------------

resource_defaults = {
  target_node    = "moo-moo"
  storage_pool   = "local-lvm"
  network_bridge = "vmbr0"
}

# NOTE: The following variables are not defined here because we are using the
# default values set in the 'variables.tf' file. You can override them here
# if this environment needs different settings.
#
# - network_defaults (gateway, cidr_mask)
# - hardware_profiles (qemu and lxc sizes)
