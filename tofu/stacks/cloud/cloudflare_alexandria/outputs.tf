# -----------------------------------------------------------------------------
# CLOUDFLARE STACK OUTPUTS
# -----------------------------------------------------------------------------

output "managed_dns_records" {
  description = "Map of created Cloudflare DNS records."
  value = {
    for k, v in cloudflare_record.dns : k => {
      id       = v.id
      hostname = v.hostname
      type     = v.type
      content  = v.content
      proxied  = v.proxied
    }
  }
}

output "resolved_zone_ids" {
  description = "Map of auto-resolved Cloudflare Zone IDs for configured domains."
  value       = local.resolved_zone_ids
}

output "tunnel_tokens" {
  description = "Map of tunnel name to its run token. Use with: cloudflared tunnel run --token <TOKEN>"
  sensitive   = true
  value = {
    for k, v in cloudflare_zero_trust_tunnel_cloudflared.tunnels : k => v.tunnel_token
  }
}
