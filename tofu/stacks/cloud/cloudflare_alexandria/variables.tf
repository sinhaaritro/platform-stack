# -----------------------------------------------------------------------------
# CLOUDFLARE CONFIGURATION VARIABLES
# -----------------------------------------------------------------------------

variable "cloudflare_api_token" {
  description = "Cloudflare API Token with permissions to edit DNS and Tunnels."
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# CONSOLIDATED CLOUDFLARE CONFIGURATION VARIABLE
# -----------------------------------------------------------------------------
variable "cloudflare" {
  description = "Consolidated Cloudflare configuration: zones, DNS, websites/apps, and remote access (tunnels + Zero Trust)."

  type = object({

    # ---------------------------------------------------------------
    # ZONES (one entry per domain you manage)
    # ---------------------------------------------------------------
    zones = optional(map(object({
      plan   = optional(string, "free") # free | pro | business | enterprise
      paused = optional(bool, false)

      settings = optional(object({
        ssl                      = optional(string, "full_strict") # off | flexible | full | strict | full_strict
        always_use_https         = optional(bool, true)
        min_tls_version          = optional(string, "1.2")
        automatic_https_rewrites = optional(bool, true)
        brotli                   = optional(bool, true)
        http3                    = optional(bool, true)
        websockets               = optional(bool, true)
        security_level           = optional(string, "medium") # off | essentially_off | low | medium | high | under_attack
      }), {})

      # ---------------------------------------------------------------
      # DNS RECORDS
      # ---------------------------------------------------------------
      dns_records = optional(list(object({
        name     = string              # "@" for apex, "www", "app", etc.
        type     = string              # A | AAAA | CNAME | TXT | MX | SRV | NS
        content  = string              # IP, hostname, or text value
        ttl      = optional(number, 1) # 1 = "auto" when proxied
        proxied  = optional(bool, true)
        priority = optional(number)    # for MX / SRV
        comment  = optional(string)
      })), [])

      # ---------------------------------------------------------------
      # PAGE RULES (redirects, cache rules, etc.)
      # ---------------------------------------------------------------
      page_rules = optional(list(object({
        target   = string # e.g. "www.example.com/*"
        priority = optional(number, 1)
        status   = optional(string, "active")
        actions  = map(string) # e.g. { forwarding_url = "https://example.com/$1", status_code = "301" }
      })), [])

      # ---------------------------------------------------------------
      # WORKERS ROUTES (attach a Worker script to a URL pattern)
      # ---------------------------------------------------------------
      workers_routes = optional(list(object({
        pattern = string # "app.example.com/api/*"
        script  = string # worker script name
      })), [])

      # ---------------------------------------------------------------
      # CACHE / FIREWALL (WAF custom rules) - lightweight, common case
      # ---------------------------------------------------------------
      firewall_rules = optional(list(object({
        description = string
        expression  = string # Cloudflare filter expression
        action      = string # block | challenge | js_challenge | allow | log | managed_challenge
        enabled     = optional(bool, true)
      })), [])

      # ---------------------------------------------------------------
      # CACHE RULES (bypass cache for specific hostnames/paths)
      # ---------------------------------------------------------------
      cache_rules = optional(list(object({
        description = string
        expression  = string              # Cloudflare filter expression, e.g. '(http.host eq "immich.example.com")'
        action      = optional(string, "bypass") # bypass | override | respect_origin
        edge_ttl    = optional(number)            # seconds, only for "override" action
      })), [])
    })), {})

    # ---------------------------------------------------------------
    # WEBSITES / APPS hosted via Cloudflare Pages
    # ---------------------------------------------------------------
    pages_projects = optional(map(object({
      production_branch = optional(string, "main")
      build_config = optional(object({
        build_command   = optional(string)
        destination_dir = optional(string, "dist")
        root_dir        = optional(string)
      }), {})
      custom_domains = optional(list(string), []) # must match a zone above
      env_vars       = optional(map(string), {})  # non-secret build/runtime vars
    })), {})

    # ---------------------------------------------------------------
    # REMOTE CONNECTION: Cloudflare Tunnel + Zero Trust Access
    # ---------------------------------------------------------------
    tunnels = optional(map(object({
      config_src = optional(string, "cloudflare") # "cloudflare" (remote-managed) or "local"

      ingress = optional(list(object({
        hostname = optional(string) # e.g. "ssh.example.com" ; omit on last catch-all rule
        service  = string          # "ssh://localhost:22", "http://localhost:8080", "rdp://localhost:3389"
        path     = optional(string)
        origin_request = optional(object({
          no_tls_verify = optional(bool, false) # skip TLS verification for self-signed certs (e.g. Proxmox)
        }))
      })), [])

      # DNS record(s) pointing hostnames at this tunnel (CNAME to <tunnel_id>.cfargotunnel.com)
      dns = optional(list(object({
        zone_name = string # key into var.cloudflare.zones
        hostname  = string
        proxied   = optional(bool, true)
      })), [])
    })), {})

    access_applications = optional(map(object({
      zone_name        = optional(string) # key into zones, if domain-scoped
      domain           = string           # full hostname the app is served on
      type             = optional(string, "self_hosted")
      session_duration = optional(string, "24h")

      policies = list(object({
        name                  = string
        decision              = optional(string, "allow") # allow | deny | non_identity | bypass
        include_emails        = optional(list(string), [])
        include_email_domains = optional(list(string), [])
        include_groups        = optional(list(string), [])
        require_mfa           = optional(bool, false)
      }))
    })), {})
  })
  default = {}
}

variable "tunnel_secrets" {
  description = "Map of tunnel name to its pre-shared secret (base64-encoded, 32+ bytes). Keys must match var.cloudflare.tunnels keys."
  type        = map(string)
  sensitive   = true
  default     = {}
}

