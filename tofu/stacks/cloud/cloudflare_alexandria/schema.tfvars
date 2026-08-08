# -----------------------------------------------------------------------------
# STACK CONFIGURATION - CLOUDFLARE EDGE / DNS (Codename: `alexandria`)
# -----------------------------------------------------------------------------

cloudflare = {
  zones = {
    "strawslabs.com" = {
      plan        = "free"
      dns_records = []
    }

    "aritrosinha.dpdns.org" = {
      plan = "free"
      dns_records = [
        {
          name    = "@"
          type    = "CNAME"
          content = "sinhaaritro.github.io"
          proxied = true
        },
        {
          name    = "www"
          type    = "CNAME"
          content = "aritrosinha.dpdns.org"
          proxied = true
        }
      ]

      cache_rules = [
        {
          description = "Bypass cache for Immich (private media)"
          expression  = "(http.host eq \"immich.hyperion.aritrosinha.dpdns.org\")"
          action      = "bypass"
        }
      ]
    }
  }

  tunnels = {
    "homelab-tunnel" = {
      ingress = [
        {
          hostname = "immich.hyperion.aritrosinha.dpdns.org"
          service  = "http://192.168.0.240:80"
        },
        {
          hostname = "grafana-hyperion.strawslabs.com"
          service  = "https://192.168.0.240:443"
          origin_request = {
            origin_server_name = "grafana-hyperion.strawslabs.com"
          }
        },
        {
          hostname       = "atlas.olympus.aritrosinha.dpdns.org"
          service        = "https://192.168.0.2:8006"
          origin_request = { no_tls_verify = true }
        },
        {
          service = "http_status:404"
        }
      ]
      dns = [
        {
          zone_name = "aritrosinha.dpdns.org"
          hostname  = "immich.hyperion"
          proxied   = true
        },
        {
          zone_name = "strawslabs.com"
          hostname  = "grafana-hyperion"
          proxied   = true
        },
        {
          zone_name = "aritrosinha.dpdns.org"
          hostname  = "atlas.olympus"
          proxied   = true
        }
      ]
    }
  }
}



