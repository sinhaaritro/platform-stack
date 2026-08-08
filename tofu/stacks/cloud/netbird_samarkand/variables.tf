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
  description = "Consolidated Netbird configuration: groups, setup keys, routes, policies, and nameserver groups."

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
      name           = string
      type           = optional(string, "reusable") # "reusable" or "one-off"
      expiry_seconds = optional(number, 7776000)    # expiry in seconds (e.g. 7776000 = 90 days)
      auto_groups    = optional(list(string), [])
      usage_limit    = optional(number, 0)
      ephemeral      = optional(bool, false)
    })), {})

    # ---------------------------------------------------------------
    # NETWORK ROUTES (Subnet routing for LAN access over mesh)
    # ---------------------------------------------------------------
    routes = optional(map(object({
      description           = optional(string, "")
      network_id            = string                     # logical grouping name, e.g. "homelab-lan"
      network               = optional(string)           # CIDR, e.g. "192.168.1.0/24" (for network routes)
      domains               = optional(list(string), []) # for domain-based routes
      peer_id               = optional(string)           # specific peer acting as router (filled post-enrollment)
      peer_groups           = optional(list(string), []) # group keys whose peers act as routers
      groups                = list(string)               # group keys that can USE this route
      access_control_groups = optional(list(string), []) # group keys for access control
      enabled               = optional(bool, true)
      masquerade            = optional(bool, true)
      metric                = optional(number, 9999)
      keep_route            = optional(bool, true)
    })), {})

    # ---------------------------------------------------------------
    # POLICIES (Access control rules between groups)
    # ---------------------------------------------------------------
    policies = optional(map(object({
      name        = optional(string)
      description = optional(string, "")
      enabled     = optional(bool, true)

      rules = list(object({
        name          = string
        action        = optional(string, "accept") # accept | drop
        bidirectional = optional(bool, true)
        enabled       = optional(bool, true)
        protocol      = optional(string, "all") # all | tcp | udp | icmp | netbird-ssh
        sources       = list(string)            # group keys
        destinations  = list(string)            # group keys
        ports         = optional(list(string), [])
      }))
    })), {})

    # ---------------------------------------------------------------
    # NAMESERVER GROUPS (DNS resolution within the mesh)
    # ---------------------------------------------------------------
    nameserver_groups = optional(map(object({
      name        = optional(string)
      description = optional(string, "")
      nameservers = list(object({
        ip      = string
        ns_type = optional(string, "udp")
        port    = optional(number, 53)
      }))
      groups                 = list(string) # group keys that use this nameserver
      domains                = optional(list(string), [])
      search_domains_enabled = optional(bool, true)
      primary                = optional(bool, false)
      enabled                = optional(bool, true)
    })), {})

    # ---------------------------------------------------------------
    # NETWORKS (Virtual network containers)
    # ---------------------------------------------------------------
    networks = optional(map(object({
      name        = string
      description = optional(string, "")
    })), {})

    # ---------------------------------------------------------------
    # NETWORK ROUTERS (Routing peers acting as gateways)
    # ---------------------------------------------------------------
    network_routers = optional(map(object({
      network_key = string
      peer_groups = list(string)
      enabled     = optional(bool, true)
      masquerade  = optional(bool, true)
      metric      = optional(number, 9000)
    })), {})

    # ---------------------------------------------------------------
    # NETWORK RESOURCES (Clientless destinations like VMs/containers)
    # ---------------------------------------------------------------
    network_resources = optional(map(object({
      name        = string
      description = optional(string, "")
      network_key = string
      address     = string
      groups      = list(string)
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
