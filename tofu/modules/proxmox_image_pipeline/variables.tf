# -----------------------------------------------------------------------------
# INPUT VARIABLES
# -----------------------------------------------------------------------------
# Inputs for the Proxmox image pipeline module.
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

variable "resources" {
  description = "The raw resources map from the stack. Scanned directly for OS types and versions."
  type        = any
}

variable "target_node" {
  description = "The target Proxmox node where image uploads are registered."
  type        = string
}

variable "target_datastore" {
  description = "The target datastore where custom images will be uploaded."
  type        = string
}

variable "local_cache_dir" {
  description = "The local directory used to download, customize, and store images."
  type        = string
  default     = "/var/tmp/tofu-artifacts/"
}

variable "default_os_type" {
  description = "The fallback OS type if not specified in resource vm_config."
  type        = string
  default     = "ubuntu"
}
