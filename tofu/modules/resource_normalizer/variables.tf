# -----------------------------------------------------------------------------
# INPUT VARIABLES - RESOURCE NORMALIZER MODULE
# -----------------------------------------------------------------------------

variable "resources" {
  description = "The raw resource definition map from the stack's tfvars."
  type        = any
  default     = {}
}

variable "user_credentials" {
  description = "Map of role-based user credentials (username, password, SSH keys)."
  sensitive   = true
  type = map(object({
    username        = string
    password        = string
    ssh_public_keys = list(string)
  }))
}

variable "target_node" {
  description = "The default Proxmox node name to fall back to."
  type        = string
}

variable "target_datastore" {
  description = "The default datastore ID to fall back to."
  type        = string
}

variable "default_os_type" {
  description = "The default OS type to fall back to."
  type        = string
  default     = "ubuntu"
}

variable "default_os_version" {
  description = "The default OS version to fall back to."
  type        = string
  default     = "24.04"
}

variable "enable_debug" {
  description = "Controls whether debug_info output is populated."
  type        = bool
  default     = true
}
