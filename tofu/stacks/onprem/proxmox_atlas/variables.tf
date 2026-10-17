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
  description = "Default datastore for guest disks (VMs/LXCs) when a resource does not set its own."
  type        = string
}

variable "image_datastore" {
  description = "Datastore for uploaded OS images (import) and LXC templates (vztmpl). Must be a 'dir' datastore that supports those content types (e.g. 'local')."
  type        = string
  default     = "local"
}

# -----------------------------------------------------------------------------
# MAIN RESOURCE DEFINITION
# -----------------------------------------------------------------------------
# This is the primary variable that defines all infrastructure for the stack.
# -----------------------------------------------------------------------------
# TODO: Add hardware template
variable "resources" {
  description = "A map of VM/LXC cluster definitions. Uses 'any' to allow heterogeneous ansible_groups per cluster — each cluster's ansible_groups map may have a completely different key/value structure. All defaults and validation are applied in the 'resource_normalizer' module."
  type        = any
  default     = {}
}

# -----------------------------------------------------------------------------
# TOPOLOGY
# -----------------------------------------------------------------------------
# The physical layer: clusters, nodes, and the NAS contract. Normalized by the
# `topology` module and emitted into the Ansible inventory. Shape (all optional):
#
#   topology = {
#     clusters = { <name> = { primary, members, vlan?, firewall?, replication?, storage? } }
#     nodes    = { <name> = { cluster, ipv4_address, ansible_user, groups,
#                             storage?, vlan?, firewall?, replication? } }
#     nas      = { provider, contract, clients }
#   }
#
# Cluster-scoped concern keys are applied by `primary` ONLY; node-scoped concern
# keys are applied on that node. Kept as `any` so the role — not the schema —
# owns validation, matching "add a disk/node by changing data, not scripts".
# -----------------------------------------------------------------------------
variable "topology" {
  description = "Physical topology: clusters, nodes, and the NAS contract. Normalized and emitted into the Ansible inventory."
  type        = any
  default     = {}
}

# -----------------------------------------------------------------------------
# NAS RCLONE CRYPT SECRET (secret)
# -----------------------------------------------------------------------------
# The rclone crypt passphrase for the offsite `vault:` remote. SECRET — supply
# it in schema.secret.tfvars (ansible-vault encrypted), NOT schema.tfvars. Tofu
# bridges it into the (gitignored) Ansible inventory, like the AWS keys.
#   nas_rclone_crypt = { password = "...", salt = "..." }
# Losing this makes the offsite backups permanently unreadable.
# -----------------------------------------------------------------------------
variable "nas_rclone_crypt" {
  description = "rclone crypt passphrase/salt for the offsite backup remote. SECRET — supply via schema.secret.tfvars."
  type        = any
  default     = {}
}

# -----------------------------------------------------------------------------
# DEBUG TOGGLE
# -----------------------------------------------------------------------------
variable "enable_debug" {
  description = "Controls whether the diagnostic output 'DEBUG_Diagnostic' is rendered. When false, returns a clean status placeholder."
  type        = bool
  default     = true
}
