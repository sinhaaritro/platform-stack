# -----------------------------------------------------------------------------
# PHASE 2: FLATTEN
# Split by type, then expand cluster.nodes into individual flat items.
# Prefixed with _ to signal these are internal pipeline steps.
# -----------------------------------------------------------------------------
locals {
  _vm_groups  = { for k, g in local.normalized_resources : k => g if g.type == "vm" }
  _lxc_groups = { for k, g in local.normalized_resources : k => g if g.type == "lxc" }

  _flattened_vms = flatten([
    for app_key, app_group in local._vm_groups : [
      for node_key, node_override in app_group.nodes : {
        app_key       = app_key
        node_key      = node_key
        app_group     = app_group
        node_override = node_override
      }
    ]
  ])

  _flattened_lxcs = flatten([
    for app_key, app_group in local._lxc_groups : [
      for node_key, node_override in app_group.nodes : {
        app_key       = app_key
        node_key      = node_key
        app_group     = app_group
        node_override = node_override
      }
    ]
  ])
}
