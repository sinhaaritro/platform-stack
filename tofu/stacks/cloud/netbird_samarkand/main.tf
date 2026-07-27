# -----------------------------------------------------------------------------
# NETBIRD RESOURCE ORCHESTRATION (samarkand)
# -----------------------------------------------------------------------------

# --- Netbird Groups ---
resource "netbird_group" "groups" {
  for_each = try(var.netbird.groups, {})

  name = coalesce(each.value.name, each.key)
}

# --- Netbird Setup Keys ---
resource "netbird_setup_key" "keys" {
  for_each = try(var.netbird.setup_keys, {})

  name        = each.value.name
  type        = each.value.type
  expires_in  = each.value.expires_in
  usage_limit = each.value.usage_limit
  ephemeral   = each.value.ephemeral

  auto_assign_groups = [
    for group_key in try(each.value.auto_assign_groups, []) :
    try(netbird_group.groups[group_key].id, group_key)
  ]
}
