# -----------------------------------------------------------------------------
# CLOUDFLARE RESOURCE ORCHESTRATION (alexandria)
# -----------------------------------------------------------------------------

# --- Cloudflare Zones (managed by IaC) ---
resource "cloudflare_zone" "zones" {
  for_each   = try(var.cloudflare.zones, {})
  account_id = var.cloudflare_account_id
  zone       = each.key
  plan       = each.value.plan
  paused     = each.value.paused

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  resolved_zone_ids = {
    for k, v in cloudflare_zone.zones : k => v.id
  }

  # Flatten explicit DNS records defined inside var.cloudflare.zones[zone].dns_records
  explicit_dns_records = flatten([
    for zone_name, zone_data in try(var.cloudflare.zones, {}) : [
      for idx, record in try(zone_data.dns_records, []) : {
        composite_key = "${zone_name}.${record.name}.${record.type}.${idx}"
        zone_id       = local.resolved_zone_ids[zone_name]
        name          = record.name
        type          = record.type
        content       = record.content
        ttl           = record.ttl
        proxied       = record.proxied
        priority      = record.priority
        comment       = record.comment != null ? record.comment : "Managed by OpenTofu alexandria stack"
      }
    ]
  ])

  # Flatten tunnel DNS records defined inside var.cloudflare.tunnels[tunnel].dns
  tunnel_dns_records = flatten([
    for tunnel_name, tunnel in try(var.cloudflare.tunnels, {}) : [
      for idx, dns_entry in try(tunnel.dns, []) : {
        composite_key = "tunnel_${tunnel_name}.${dns_entry.hostname}.${idx}"
        zone_id       = local.resolved_zone_ids[dns_entry.zone_name]
        name          = dns_entry.hostname
        type          = "CNAME"
        content       = "${try(cloudflare_zero_trust_tunnel_cloudflared.tunnels[tunnel_name].id, "")}.cfargotunnel.com"
        ttl           = 1
        proxied       = dns_entry.proxied
        priority      = null
        comment       = "Tunnel CNAME for ${tunnel_name}"
      }
    ]
  ])

  all_dns_records = concat(local.explicit_dns_records, local.tunnel_dns_records)

  dns_record_map = {
    for rec in local.all_dns_records : rec.composite_key => rec
  }
}

# --- Cloudflare DNS Records ---
resource "cloudflare_record" "dns" {
  for_each = local.dns_record_map

  zone_id  = each.value.zone_id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.content
  ttl      = each.value.ttl
  proxied  = each.value.proxied
  priority = each.value.priority
  comment  = each.value.comment
}

# --- Cloudflare Zero Trust Tunnels ---
resource "cloudflare_zero_trust_tunnel_cloudflared" "tunnels" {
  for_each = try(var.cloudflare.tunnels, {})

  account_id = var.cloudflare_account_id
  name       = each.key
  secret     = try(var.tunnel_secrets[each.key], base64encode("placeholder-replace-me-32bytes!!"))
}

# --- Cloudflare Tunnel Configuration (Ingress Rules) ---
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "tunnel_configs" {
  for_each = {
    for k, v in try(var.cloudflare.tunnels, {}) : k => v
    if length(try(v.ingress, [])) > 0
  }

  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.tunnels[each.key].id

  config {
    dynamic "ingress_rule" {
      for_each = each.value.ingress
      content {
        hostname = ingress_rule.value.hostname
        service  = ingress_rule.value.service
        path     = ingress_rule.value.path

        dynamic "origin_request" {
          for_each = ingress_rule.value.origin_request != null ? [ingress_rule.value.origin_request] : []
          content {
            no_tls_verify        = origin_request.value.no_tls_verify
            origin_server_name   = origin_request.value.origin_server_name
          }
        }
      }
    }
  }
}

# --- Cloudflare Zero Trust Access Applications ---
resource "cloudflare_zero_trust_access_application" "apps" {
  for_each = try(var.cloudflare.access_applications, {})

  account_id       = var.cloudflare_account_id
  zone_id          = each.value.zone_name != null ? try(local.resolved_zone_ids[each.value.zone_name], null) : null
  name             = each.key
  domain           = each.value.domain
  type             = each.value.type
  session_duration = each.value.session_duration
}

locals {
  access_policies = flatten([
    for app_key, app in try(var.cloudflare.access_applications, {}) : [
      for policy in app.policies : {
        composite_key         = "${app_key}.${policy.name}"
        application_id        = cloudflare_zero_trust_access_application.apps[app_key].id
        name                  = policy.name
        decision              = policy.decision
        include_emails        = policy.include_emails
        include_email_domains = policy.include_email_domains
      }
    ]
  ])
  access_policy_map = {
    for pol in local.access_policies : pol.composite_key => pol
  }
}

resource "cloudflare_zero_trust_access_policy" "policies" {
  for_each = local.access_policy_map

  account_id     = var.cloudflare_account_id
  application_id = each.value.application_id
  name           = each.value.name
  decision       = each.value.decision
  precedence     = 1

  dynamic "include" {
    for_each = [1]
    content {
      email        = length(each.value.include_emails) > 0 ? each.value.include_emails : null
      email_domain = length(each.value.include_email_domains) > 0 ? each.value.include_email_domains : null
    }
  }
}


# --- Cloudflare Cache Rules (Bypass cache for specific services) ---
locals {
  cache_rules_by_zone = {
    for zone_name, zone_data in try(var.cloudflare.zones, {}) :
    zone_name => try(zone_data.cache_rules, [])
    if length(try(zone_data.cache_rules, [])) > 0
  }
}

resource "cloudflare_ruleset" "cache_rules" {
  for_each = local.cache_rules_by_zone

  zone_id     = local.resolved_zone_ids[each.key]
  name        = "Cache rules for ${each.key}"
  description = "Managed by OpenTofu alexandria stack"
  kind        = "zone"
  phase       = "http_request_cache_settings"

  dynamic "rules" {
    for_each = each.value
    content {
      description = rules.value.description
      expression  = rules.value.expression
      action      = "set_cache_settings"

      action_parameters {
        cache = rules.value.action == "bypass" ? false : true

        dynamic "edge_ttl" {
          for_each = rules.value.edge_ttl != null ? [rules.value.edge_ttl] : []
          content {
            mode    = "override_origin"
            default = edge_ttl.value
          }
        }
      }

      enabled = true
    }
  }
}

# --- Generated Ansible Inventory Vars (ansible/inventory.d/cloudflare_alexandria.yml) ---
resource "local_sensitive_file" "ansible_inventory" {
  filename        = "${path.module}/../../../../ansible/inventory.d/cloudflare_alexandria.yml"
  file_permission = "0600"
  content = join("\n", concat(
    ["all:", "  vars:"],
    [for k, v in cloudflare_zero_trust_tunnel_cloudflared.tunnels :
      "    cloudflare_tunnel_token_${replace(k, "-", "_")}: \"${v.tunnel_token}\""
    ],
    [for k, v in cloudflare_zero_trust_tunnel_cloudflared.tunnels :
      "    cloudflare_tunnel_id_${replace(k, "-", "_")}: \"${v.id}\""
    ],
    [for k, v in local.resolved_zone_ids :
      "    cloudflare_zone_id_${replace(replace(k, ".", "_"), "-", "_")}: \"${v}\""
    ],
    [""]
  ))
}
