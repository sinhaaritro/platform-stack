# -----------------------------------------------------------------------------
# ENVIRONMENT GUARDRAIL
#
# This variable is a critical safety feature. It is used in a precondition
# check to ensure that the loaded .tfvars file matches the intended
# OpenTofu workspace, preventing accidental cross-environment changes.
# -----------------------------------------------------------------------------

variable "environment_name" {
  type        = string
  description = "The name of the current environment (e.g., 'sandbox', 'public'). Must match the OpenTofu workspace name."
}

# -----------------------------------------------------------------------------
# PROXMOX PROVIDER CONFIGURATION
#
# This section defines the connection parameters for a single Proxmox
# environment (e.g., sandbox, public, etc.).
# -----------------------------------------------------------------------------

variable "proxmox_connection" {
  type = object({
    url = string
    insecure_tls = bool
    auth_method  = string # Must be 'password' or 'token'

    # The following two attributes are optional. You must define the one
    # that corresponds to the chosen 'auth_method'.
    password_auth = optional(object({
      user     = string
      password = string
    }))
    token_auth = optional(object({
      id     = string
      secret = string
    }))
  })
  description = "An object containing all necessary details to connect to a Proxmox API endpoint. The URL for the Proxmox API (e.g., https://192.168.1.10:8006/api2/json)."
  sensitive   = true

  validation {
    condition     = var.proxmox_connection.auth_method == "password" || var.proxmox_connection.auth_method == "token"
    error_message = "The 'auth_method' attribute must be either 'password' or 'token'."
  }
  validation {
    condition     = !(var.proxmox_connection.auth_method == "password" && var.proxmox_connection.password_auth == null)
    error_message = "If 'auth_method' is 'password', the 'password_auth' object must be provided."
  }
  validation {
    condition     = !(var.proxmox_connection.auth_method == "token" && var.proxmox_connection.token_auth == null)
    error_message = "If 'auth_method' is 'token', the 'token_auth' object must be provided."
  }
}

# -----------------------------------------------------------------------------
# ENVIRONMENT-WIDE DEFAULTS
#
# These variables define the common placement and network settings for all
# resources created within a single Proxmox environment.
# -----------------------------------------------------------------------------

variable "resource_defaults" {
  type = object({
    target_node    = string
    storage_pool   = string
    network_bridge = string
  })
  description = "Default placement and storage settings for the environment."
  default = {
    target_node    = "pve"
    storage_pool   = "local-thin"
    network_bridge = "vmbr0"
  }
}

variable "network_defaults" {
  type = object({
    gateway   = string
    cidr_mask = number
  })
  description = "Default network gateway and CIDR mask for the environment."
  default = {
    gateway   = "192.168.0.1"
    cidr_mask = 24
  }
}


# -----------------------------------------------------------------------------
# HARDWARE AND USER CONFIGURATION
#
# These variables define reusable common sizes for hardware and a
# default user profile for Cloud-Init.
# -----------------------------------------------------------------------------

variable "hardware_profiles" {
  type = object({
    qemu = map(object({
      cores     = number
      memory    = number
      disk_size = string
    }))
    lxc = map(object({
      cores       = number
      memory      = number
      rootfs_size = string
    }))
  })
  description = "A collection of hardware profiles for both QEMU VMs and LXC containers."
  default = {
    qemu = {
      "small" = {
        cores     = 1
        memory    = 1024 # 1GB
        disk_size = "10G"
      },
      "medium" = {
        cores     = 2
        memory    = 2048 # 2GB
        disk_size = "20G"
      },
      "large" = {
        cores     = 4
        memory    = 4096 # 4GB
        disk_size = "40G"
      }
    },
    lxc = {
      "small" = {
        cores       = 1
        memory      = 512 # 512MB
        rootfs_size = "4G"
      },
      "medium" = {
        cores       = 2
        memory      = 1024 # 1GB
        rootfs_size = "8G"
      }
    }
  }
}

variable "user_profile" {
  type = object({
    username        = string
    package_upgrade = bool
  })
  description = "An object containing non-sensitive user profile information, like the username."
  default = {
    username        = "dev"
    package_upgrade = true
  }
}

variable "user_credentials" {
  type = object({
    password        = string
    ssh_public_keys = list(string)
  })
  description = "An object containing sensitive user credentials like the password and SSH keys."
  sensitive   = true
}

# -----------------------------------------------------------------------------
# MASTER RESOURCE DEFINITION
#
# This is the primary variable for this project. It is a map of "resource
# groups". Each group represents a cluster or a set of standalone machines
# that are managed together. This allows you to define all your
# infrastructure declaratively.
# -----------------------------------------------------------------------------

variable "resource_groups" {
  type = map(object({
    # --- Control & Metadata ---
    enabled               = bool
    type                  = string # Must be 'qemu' or 'lxc'
    template              = string
    hardware_profile_key  = string
    tags                  = list(string)

    # --- Node Definitions ---
    nodes = map(object({
      id = number
      ip = string
    }))
  }))
  description = "The master map defining all resource groups (clusters, standalone nodes) to be created in the environment."

  default = {} # Default to an empty map so plan doesn't fail if no groups are defined.

  validation {
    condition     = alltrue([for group in var.resource_groups : contains(["qemu", "lxc"], group.type)])
    error_message = "Each resource group's 'type' attribute must be either 'qemu' or 'lxc'."
  }

  validation {
    # This complex condition checks that the hardware profile key is valid for the given resource type.
    condition = alltrue([
      for group in var.resource_groups :
      (group.type == "qemu" && can(var.hardware_profiles.qemu[group.hardware_profile_key])) ||
      (group.type == "lxc" && can(var.hardware_profiles.lxc[group.hardware_profile_key]))
    ])
    error_message = "The 'hardware_profile_key' for each resource group must be a valid key in the 'hardware_profiles' map that corresponds to its 'type' (qemu or lxc)."
  }
}