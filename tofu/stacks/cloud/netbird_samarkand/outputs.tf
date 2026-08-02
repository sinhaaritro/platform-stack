# -----------------------------------------------------------------------------
# NETBIRD STACK OUTPUTS
# -----------------------------------------------------------------------------

output "setup_keys" {
  description = "Map of created Netbird setup keys, keyed by input name."
  sensitive   = true
  value = {
    for k, v in netbird_setup_key.keys : k => {
      id    = v.id
      key   = v.key
      name  = v.name
      type  = v.type
      valid = v.valid
    }
  }
}

output "groups" {
  description = "Map of created Netbird group IDs."
  value = {
    for k, v in netbird_group.groups : k => {
      id   = v.id
      name = v.name
    }
  }
}

output "routes" {
  description = "Map of created Netbird routes."
  value = {
    for k, v in netbird_route.routes : k => {
      id          = v.id
      network_id  = v.network_id
      network     = v.network
      description = v.description
    }
  }
}

output "policies" {
  description = "Map of created Netbird policies."
  value = {
    for k, v in netbird_policy.policies : k => {
      id      = v.id
      name    = v.name
      enabled = v.enabled
    }
  }
}
