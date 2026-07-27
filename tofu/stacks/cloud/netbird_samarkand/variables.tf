# -----------------------------------------------------------------------------
# NETBIRD CONFIGURATION VARIABLES
# -----------------------------------------------------------------------------

variable "netbird_api_url" {
  description = "The API base URL for the Netbird management server."
  type        = string
  default     = "https://api.netbird.io"
}

variable "netbird_management_token" {
  description = "Management API token or Personal Access Token for Netbird."
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# CONSOLIDATED NETBIRD CONFIGURATION VARIABLE
# -----------------------------------------------------------------------------
variable "netbird" {
  description = "Consolidated Netbird configuration: groups, setup keys, and network policies."

  type = object({
    # ---------------------------------------------------------------
    # GROUPS
    # ---------------------------------------------------------------
    groups = optional(map(object({
      name = optional(string)
    })), {})

    # ---------------------------------------------------------------
    # SETUP KEYS
    # ---------------------------------------------------------------
    setup_keys = optional(map(object({
      name               = string
      type               = optional(string, "reusable") # "reusable" or "one-off"
      expires_in         = optional(number, 7776000)   # expiry in seconds (e.g. 7776000 = 90 days)
      auto_assign_groups = optional(list(string), [])
      usage_limit        = optional(number, 0)
      ephemeral          = optional(bool, false)
    })), {})
  })
  default = {}
}

# -----------------------------------------------------------------------------
# DEBUG TOGGLE
# -----------------------------------------------------------------------------
variable "enable_debug" {
  description = "Controls whether debug info output is rendered."
  type        = bool
  default     = true
}
