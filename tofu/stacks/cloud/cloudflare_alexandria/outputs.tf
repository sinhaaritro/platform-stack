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


