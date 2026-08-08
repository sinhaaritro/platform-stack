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

  name           = each.value.name
  type           = each.value.type
  expiry_seconds = each.value.expiry_seconds
  usage_limit    = each.value.usage_limit
  ephemeral      = each.value.ephemeral

  auto_groups = [
    for group_key in try(each.value.auto_groups, []) :
    try(netbird_group.groups[group_key].id, group_key)
  ]
}

# --- Netbird Network Routes ---
resource "netbird_route" "routes" {
  for_each = try(var.netbird.routes, {})

  network_id  = each.value.network_id
  network     = each.value.network
  description = coalesce(each.value.description, each.key)
  peer        = each.value.peer_id
  masquerade  = each.value.masquerade
  metric      = each.value.metric
  keep_route  = each.value.keep_route
  enabled     = each.value.enabled

  groups = [
    for group_key in each.value.groups :
    try(netbird_group.groups[group_key].id, group_key)
  ]

  access_control_groups = [
    for group_key in try(each.value.access_control_groups, []) :
    try(netbird_group.groups[group_key].id, group_key)
  ]

  peer_groups = [
    for group_key in try(each.value.peer_groups, []) :
    try(netbird_group.groups[group_key].id, group_key)
  ]
}

# --- Netbird Policies ---
resource "netbird_policy" "policies" {
  for_each = try(var.netbird.policies, {})

  name    = coalesce(each.value.name, each.key)
  enabled = each.value.enabled

  dynamic "rule" {
    for_each = each.value.rules
    content {
      name          = rule.value.name
      action        = rule.value.action
      bidirectional = rule.value.bidirectional
      enabled       = rule.value.enabled
      protocol      = rule.value.protocol
      ports         = length(rule.value.ports) > 0 ? rule.value.ports : null

      sources = [
        for group_key in rule.value.sources :
        try(netbird_group.groups[group_key].id, group_key)
      ]

      destinations = [
        for group_key in rule.value.destinations :
        try(netbird_group.groups[group_key].id, group_key)
      ]
    }
  }
}

# --- Netbird Nameserver Groups ---
resource "netbird_nameserver_group" "nameservers" {
  for_each = try(var.netbird.nameserver_groups, {})

  name                   = coalesce(each.value.name, each.key)
  description            = each.value.description
  primary                = each.value.primary
  enabled                = each.value.enabled
  search_domains_enabled = each.value.search_domains_enabled
  domains                = each.value.domains

  nameservers = each.value.nameservers

  groups = [
    for group_key in each.value.groups :
    try(netbird_group.groups[group_key].id, group_key)
  ]
}

# --- Netbird Networks ---
resource "netbird_network" "networks" {
  for_each = try(var.netbird.networks, {})

  name        = each.value.name
  description = coalesce(each.value.description, each.key)
}

# --- Netbird Network Routers ---
resource "netbird_network_router" "routers" {
  for_each = try(var.netbird.network_routers, {})

  network_id  = netbird_network.networks[each.value.network_key].id
  peer_groups = [
    for group_key in each.value.peer_groups :
    try(netbird_group.groups[group_key].id, group_key)
  ]
  enabled     = each.value.enabled
  masquerade  = each.value.masquerade
  metric      = each.value.metric
}

# --- Netbird Network Resources ---
resource "netbird_network_resource" "resources" {
  for_each = try(var.netbird.network_resources, {})

  name        = each.value.name
  description = coalesce(each.value.description, each.key)
  network_id  = netbird_network.networks[each.value.network_key].id
  address     = each.value.address

  groups = [
    for group_key in each.value.groups :
    try(netbird_group.groups[group_key].id, group_key)
  ]
}

# --- Generated Ansible Inventory Vars (ansible/inventory.d/netbird_samarkand.yml) ---
resource "local_sensitive_file" "ansible_inventory" {
  filename        = "${path.module}/../../../../ansible/inventory.d/netbird_samarkand.yml"
  file_permission = "0600"
  content = join("\n", concat(
    ["all:", "  vars:"],
    [for k, v in netbird_setup_key.keys :
      "    netbird_setup_key_${replace(k, "-", "_")}: \"${v.key}\""
    ],
    [""]
  ))
}
