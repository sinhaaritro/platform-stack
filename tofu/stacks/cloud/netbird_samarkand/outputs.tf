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
