# -----------------------------------------------------------------------------
# PROMOX CONNECTION VARIABLES
# -----------------------------------------------------------------------------

variable "proxmox_connection" {
  description = "Configuration for connecting to the Proxmox API. Includes endpoint URL and authentication details. The entire object is marked as sensitive."
  sensitive   = true

  type = object({
    url          = string
    insecure_tls = bool
    auth_method  = string # Must be 'password' or 'token' or 'ticket'
    password_auth = optional(object({
      user     = string
      password = string
    }))
    token_auth = optional(object({
      id     = string
      secret = string
    }))
    ticket_auth = optional(object({
      auth_ticket           = string
      csrf_prevention_token = string
    }))
  })

  validation {
    condition     = contains(["password", "token", "ticket"], var.proxmox_connection.auth_method)
    error_message = "The auth_method must be either 'password', 'token', or 'ticket'."
  }

  validation {
    condition = (
      (var.proxmox_connection.auth_method == "password" && var.proxmox_connection.password_auth != null) ||
      (var.proxmox_connection.auth_method == "token" && var.proxmox_connection.token_auth != null) ||
      (var.proxmox_connection.auth_method == "ticket" && var.proxmox_connection.ticket_auth != null)
    )
    error_message = "Invalid authentication configuration. The configuration object corresponding to the selected auth_method (password_auth, token_auth, or ticket_auth) must be provided. The other auth block must be omitted."
  }
}

# -----------------------------------------------------------------------------
# CLOUD-INIT SECRET DEFINITIONS
# -----------------------------------------------------------------------------
# This variable defines a map of role-based secret credentials. Each key
# represents a role (e.g., "web_admins", "db_admins"), and the value contains
# the sensitive user account details for that role.
# This entire variable should be populated in a separate, encrypted .tfvars file.
# -----------------------------------------------------------------------------
variable "user_credentials" {
  description = "Defines the secret user credentials (username, password and SSH keys) for cloud-init."
  # sensitive   = true
  type = map(object({
    username        = string
    password        = string
    ssh_public_keys = list(string)
  }))

  validation {
    condition = alltrue([
      for cred in var.user_credentials :
      (length(trimspace(cred.username)) > 1 && (cred.password != "" || length(cred.ssh_public_keys) > 0))
    ])
    error_message = "Validation failed for 'user_credentials'. Each credential entry must have a non-empty 'username' AND either a 'password' or at least one 'ssh_public_key'."
  }
}

# -----------------------------------------------------------------------------
# STACK TARGETING VARIABLES
# -----------------------------------------------------------------------------
variable "target_node" {
  description = "The Proxmox node this stack will manage."
  type        = string
}

variable "target_datastore" {
  description = "The datastore on the target node to use for image uploads."
  type        = string
}

# -----------------------------------------------------------------------------
# MAIN RESOURCE DEFINITION
# -----------------------------------------------------------------------------
# This is the primary variable that defines all infrastructure for the stack.
# -----------------------------------------------------------------------------
# TODO: Add hardware template
variable "resources" {
  description = "A map of virtual machines or LXC to create. The map key is used as the default VM name."
  # This type definition is now a complete and accurate blueprint of the expected data.
  type = map(object({
    # Control & Metadata
    enabled = optional(bool, true)
    type    = string # Must be 'vm' or 'lxc'
    tags    = optional(list(string))

    # We can define a this cluster level that will be passed down at the node level.
    node_name             = optional(string)
    description           = optional(string, "Managed by OpenTofu")
    on_boot               = optional(bool, false)
    started               = optional(bool, true)
    cpu_cores             = optional(number, 1)
    cpu_sockets           = optional(number, 1)
    memory_size           = optional(number, 1024)
    disk_datastore_id     = optional(string)
    source_image_path     = optional(string)
    disk_size             = optional(number, 8)
    disk_ssd              = optional(bool, false)
    vlan_bridge           = optional(string, "vmbr0")
    vlan_id               = optional(number, 1)
    cloud_init_secret_key = optional(string)

    # Node Definitions
    # We can define a node level that will be override the values passed from the cluster level.
    nodes = map(object({
      vm_id                 = number
      enabled               = optional(bool)
      node_name             = optional(string)
      description           = optional(string)
      tags                  = optional(list(string))
      on_boot               = optional(bool)
      started               = optional(bool)
      cpu_cores             = optional(number)
      cpu_sockets           = optional(number)
      memory_size           = optional(number)
      disk_datastore_id     = optional(string)
      source_image_path     = optional(string)
      disk_size             = optional(number)
      disk_ssd              = optional(bool)
      vlan_bridge           = optional(string)
      vlan_id               = optional(number)
      ipv4_address          = optional(string, "dhcp")
      cloud_init_secret_key = optional(string)
    }))
  }))

  validation {
    condition = alltrue([
      for cluster in var.resources :
      cluster.type == "vm" || cluster.type == "lxc"
    ])
    error_message = "Validation failed for 'type'. Each cluster entry must be of 'vm' or 'lxc'."
  }

  default = {}
}
