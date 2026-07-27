# -----------------------------------------------------------------------------
# STACK CONFIGURATION - CLOUDFLARE EDGE / DNS (Codename: `alexandria`)
# -----------------------------------------------------------------------------

cloudflare_account_id = "701f3c4f126a1895cde973c3466880df"

cloudflare = {
  zones = {
    "strawslabs.com" = {
      plan = "free"

      dns_records = [
        # {
        #   name    = "grafana.hyperion"
        #   type    = "CNAME"
        #   content = "homelab-tunnel.cfargotunnel.com"
        #   proxied = true
        # }
      ]
    }
  }

  tunnels = {
    # "homelab-tunnel" = {
    #   ingress = [
    #     {
    #       hostname = "grafana.hyperion.strawslabs.com"
    #       service  = "http://192.168.1.150:3000"
    #     },
    #     {
    #       service  = "http_status:404"
    #     }
    #   ]
    #   dns = [
    #     {
    #       zone_name = "strawslabs.com"
    #       hostname  = "grafana.hyperion"
    #       proxied   = true
    #     }
    #   ]
    # }
  }
}



