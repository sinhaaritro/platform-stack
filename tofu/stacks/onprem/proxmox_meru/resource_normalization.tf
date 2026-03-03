# =============================================================================
# RESOURCE NORMALIZATION PIPELINE
# =============================================================================
# Transforms raw 'var.resources' (type = any) into two clean, flat,
# fully-resolved maps for use by the modules in main.tf:
#
#   local.final_vm_list   → map of enabled VMs,  keyed by node_key
#   local.final_lxc_list  → map of enabled LXCs, keyed by node_key
#
# Pipeline:
#   Phase 1: normalized_resources  → validate + apply all defaults
#   Phase 2: _flattened_vms/lxcs  → expand cluster.nodes into flat items
#   Phase 3: final_vm_list/lxc_list → resolve inheritance, filter disabled
#
# Validation strategy: 'try(field, default)' for optional fields (silent).
#   For mandatory fields or structural errors: "ERROR: ..."[999] causes a
#   plan-time failure that prints the error string in OpenTofu's output.
# =============================================================================

# -----------------------------------------------------------------------------
# PHASE 1: NORMALIZE
# Apply defaults and validate mandatory fields / discriminating union.
# -----------------------------------------------------------------------------
locals {
  normalized_resources = {
    for cluster_key, cluster in var.resources : cluster_key => merge(

      # ── VALIDATION: Discriminating Union ─────────────────────────────────
      # type="vm"  → vm_config must be present,  lxc_config must be absent
      # type="lxc" → lxc_config must be present, vm_config must be absent
      (
        (try(cluster.type, "") == "vm" && try(cluster.vm_config, null) != null && try(cluster.lxc_config, null) == null) ||
        (try(cluster.type, "") == "lxc" && try(cluster.lxc_config, null) != null && try(cluster.vm_config, null) == null)
        ) ? {} : {
        _error = "VALIDATION ERROR for '${cluster_key}': 'type' must be 'vm' or 'lxc', with only the matching config block (vm_config/lxc_config) provided and the other omitted." [999]
      },

      # ── NORMALIZATION ─────────────────────────────────────────────────────
      {
        # MANDATORY — no sensible default, fail loudly with a readable message
        type = try(cluster.type, "ERROR: 'type' is required for resource '${cluster_key}'. Must be 'vm' or 'lxc'." [999])

        # OPTIONAL — safe defaults mirror the old optional(T, default) schema
        enabled         = try(cluster.enabled, true)
        node_name       = try(cluster.node_name, null)
        description     = try(cluster.description, "Managed by OpenTofu")
        tags            = try(cluster.tags, [])
        on_boot         = try(cluster.on_boot, false)
        started         = try(cluster.started, true)
        cloud_init_user = try(cluster.cloud_init_user, null)

        # KEY POINT: ansible_groups passes through completely unmodified.
        # Because var.resources is `any`, OpenTofu never tries to unify the
        # type schema — each cluster can have a structurally different map.
        ansible_groups = try(cluster.ansible_groups, {})

        vm_config = try(cluster.vm_config, null) != null ? {
          cpu_cores         = try(cluster.vm_config.cpu_cores, 1)
          cpu_sockets       = try(cluster.vm_config.cpu_sockets, 1)
          memory_size       = try(cluster.vm_config.memory_size, 1024)
          disk_datastore_id = try(cluster.vm_config.disk_datastore_id, null)
          disk_size         = try(cluster.vm_config.disk_size, 8)
          disk_ssd          = try(cluster.vm_config.disk_ssd, false)
          vlan_bridge       = try(cluster.vm_config.vlan_bridge, "vmbr0")
          vlan_id           = try(cluster.vm_config.vlan_id, 0)
          ipv4_gateway      = try(cluster.vm_config.ipv4_gateway, null)
          os_version        = try(cluster.vm_config.os_version, null)
          additional_disks  = try(cluster.vm_config.additional_disks, [])
        } : null

        lxc_config = try(cluster.lxc_config, null) != null ? {
          unprivileged      = try(cluster.lxc_config.unprivileged, true)
          nesting           = try(cluster.lxc_config.nesting, true)
          fuse              = try(cluster.lxc_config.fuse, false)
          keyctl            = try(cluster.lxc_config.keyctl, true)
          template_file_id  = try(cluster.lxc_config.template_file_id, null)
          os_type           = try(cluster.lxc_config.os_type, null)
          disk_datastore_id = try(cluster.lxc_config.disk_datastore_id, null)
          disk_size         = try(cluster.lxc_config.disk_size, 2)
          cpu_cores         = try(cluster.lxc_config.cpu_cores, 1)
          memory_size       = try(cluster.lxc_config.memory_size, 1024)
          vlan_bridge       = try(cluster.lxc_config.vlan_bridge, "vmbr0")
          vlan_id           = try(cluster.lxc_config.vlan_id, 0)
          ipv4_gateway      = try(cluster.lxc_config.ipv4_gateway, null)
        } : null

        nodes = {
          for node_key, node in try(cluster.nodes, {}) : node_key => {
            # MANDATORY
            vm_id = try(node.vm_id, "ERROR: 'vm_id' is required but missing for node '${node_key}' in cluster '${cluster_key}'." [999])

            # OPTIONAL — node overrides default to null = "not set, inherit from cluster"
            # A real value here would shadow the cluster-level value even when
            # the user did not intend to override it.
            enabled         = try(node.enabled, null)
            node_name       = try(node.node_name, null)
            description     = try(node.description, null)
            tags            = try(node.tags, [])
            on_boot         = try(node.on_boot, null)
            started         = try(node.started, null)
            cloud_init_user = try(node.cloud_init_user, null)
            ansible_groups  = try(node.ansible_groups, {})

            vm_config = try(node.vm_config, null) != null ? {
              cpu_cores         = try(node.vm_config.cpu_cores, null)
              cpu_sockets       = try(node.vm_config.cpu_sockets, null)
              memory_size       = try(node.vm_config.memory_size, null)
              disk_datastore_id = try(node.vm_config.disk_datastore_id, null)
              disk_size         = try(node.vm_config.disk_size, null)
              disk_ssd          = try(node.vm_config.disk_ssd, null)
              vlan_bridge       = try(node.vm_config.vlan_bridge, null)
              vlan_id           = try(node.vm_config.vlan_id, null)
              ipv4_address      = try(node.vm_config.ipv4_address, "dhcp")
              ipv4_gateway      = try(node.vm_config.ipv4_gateway, null)
              os_version        = try(node.vm_config.os_version, null)
              additional_disks  = try(node.vm_config.additional_disks, null)
            } : null

            lxc_config = try(node.lxc_config, null) != null ? {
              unprivileged      = try(node.lxc_config.unprivileged, null)
              nesting           = try(node.lxc_config.nesting, null)
              fuse              = try(node.lxc_config.fuse, null)
              keyctl            = try(node.lxc_config.keyctl, null)
              template_file_id  = try(node.lxc_config.template_file_id, null)
              os_type           = try(node.lxc_config.os_type, null)
              disk_datastore_id = try(node.lxc_config.disk_datastore_id, null)
              disk_size         = try(node.lxc_config.disk_size, null)
              cpu_cores         = try(node.lxc_config.cpu_cores, null)
              memory_size       = try(node.lxc_config.memory_size, null)
              vlan_bridge       = try(node.lxc_config.vlan_bridge, null)
              vlan_id           = try(node.lxc_config.vlan_id, null)
              ipv4_address      = try(node.lxc_config.ipv4_address, "dhcp")
              ipv4_gateway      = try(node.lxc_config.ipv4_gateway, null)
            } : null
          }
        }
      }
    )
  }
}

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

# -----------------------------------------------------------------------------
# PHASE 3: RESOLVE & FILTER
# Merge cluster → node inheritance via coalesce(). Resolve credentials.
# Filter out disabled nodes. Output: final_vm_list + final_lxc_list.
# -----------------------------------------------------------------------------
locals {
  # ── OUTPUT: final_vm_list ──────────────────────────────────────────────────
  final_vm_list = {
    for item in local._flattened_vms : item.node_key => {
      app_key = item.app_key
      name    = item.node_key
      type    = item.app_group.type
      enabled = coalesce(item.node_override.enabled, item.app_group.enabled)
      vm_id   = item.node_override.vm_id

      node_name = (
        (item.node_override.node_name != null || item.app_group.node_name != null) ?
        coalesce(item.node_override.node_name, item.app_group.node_name) :
        "ERROR: 'node_name' is not defined for VM '${item.node_key}' in application '${item.app_key}'. Please set it at the application or node level." [999]
      )
      description = coalesce(item.node_override.description, item.app_group.description)
      tags = sort(distinct(concat(
        ["OpenTofu"],
        coalesce(item.app_group.tags, []),
        coalesce(item.node_override.tags, [])
      )))
      on_boot = coalesce(item.node_override.on_boot, item.app_group.on_boot)
      started = coalesce(item.node_override.started, item.app_group.started)

      # Hardware
      cpu_cores   = coalesce(item.node_override.vm_config.cpu_cores, item.app_group.vm_config.cpu_cores)
      cpu_sockets = coalesce(item.node_override.vm_config.cpu_sockets, item.app_group.vm_config.cpu_sockets)
      memory_size = coalesce(item.node_override.vm_config.memory_size, item.app_group.vm_config.memory_size)

      # Disk
      disk_datastore_id = coalesce(item.node_override.vm_config.disk_datastore_id, item.app_group.vm_config.disk_datastore_id, var.target_datastore)
      disk_size         = coalesce(item.node_override.vm_config.disk_size, item.app_group.vm_config.disk_size)
      disk_ssd          = coalesce(item.node_override.vm_config.disk_ssd, item.app_group.vm_config.disk_ssd)

      # Network
      vlan_bridge = coalesce(item.node_override.vm_config.vlan_bridge, item.app_group.vm_config.vlan_bridge)
      vlan_id     = coalesce(item.node_override.vm_config.vlan_id, item.app_group.vm_config.vlan_id)
      os_version  = coalesce(item.node_override.vm_config.os_version, item.app_group.vm_config.os_version)

      # Additional Disks — node overrides cluster; falls back to []
      additional_disks = (
        item.node_override.vm_config != null && item.node_override.vm_config.additional_disks != null ?
        item.node_override.vm_config.additional_disks :
        item.app_group.vm_config != null && item.app_group.vm_config.additional_disks != null ?
        item.app_group.vm_config.additional_disks :
        []
      )

      # Cloud-Init
      ipv4_address = item.node_override.vm_config.ipv4_address
      ipv4_gateway = coalesce(item.node_override.vm_config.ipv4_gateway, item.app_group.vm_config.ipv4_gateway, "192.168.0.1")

      user_account_username = (
        (var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")] != null &&
          var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].username != null &&
        trimspace(var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].username) != "") ?
        var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].username :
        "ERROR: 'username' not found for VM '${item.node_key}'. Check secret '${coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")}' in 'user_credentials'." [999]
      )
      user_account_password = (
        (var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")] != null &&
          var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].password != null &&
        trimspace(var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].password) != "") ?
        var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].password :
        "ERROR: 'password' not found for VM '${item.node_key}'. Check secret '${coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")}' in 'user_credentials'." [999]
      )
      user_account_keys = (
        (var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")] != null &&
          var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].ssh_public_keys != null &&
        var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].ssh_public_keys != []) ?
        var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].ssh_public_keys :
        "ERROR: 'ssh_public_keys' not found for VM '${item.node_key}'. Check secret '${coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")}' in 'user_credentials'." [999]
      )

      # ansible_groups: merge cluster-level and node-level groups.
      # Node values win on key conflicts. Each VM may have a completely
      # different map structure — this is the whole point of type=any.
      ansible_groups = {
        for group_name in distinct(concat(
          keys(coalesce(item.app_group.ansible_groups, {})),
          keys(coalesce(item.node_override.ansible_groups, {}))
        )) :
        group_name => merge(
          try(item.app_group.ansible_groups[group_name], {}),
          try(item.node_override.ansible_groups[group_name], {})
        )
      }
    }
    if coalesce(item.node_override.enabled, item.app_group.enabled) && item.app_group.type == "vm"
  }

  # ── OUTPUT: final_lxc_list ─────────────────────────────────────────────────
  final_lxc_list = {
    for item in local._flattened_lxcs : item.node_key => {
      app_key = item.app_key
      name    = item.node_key
      type    = item.app_group.type
      enabled = coalesce(item.node_override.enabled, item.app_group.enabled)
      vm_id   = item.node_override.vm_id

      node_name    = coalesce(item.node_override.node_name, item.app_group.node_name, var.target_node)
      description  = coalesce(item.node_override.description, item.app_group.description)
      tags         = sort(distinct(concat(["OpenTofu"], coalesce(item.app_group.tags, []), coalesce(item.node_override.tags, []))))
      on_boot      = coalesce(item.node_override.on_boot, item.app_group.on_boot)
      started      = coalesce(item.node_override.started, item.app_group.started)
      unprivileged = coalesce(item.node_override.lxc_config.unprivileged, item.app_group.lxc_config.unprivileged)

      nesting = coalesce(item.node_override.lxc_config.nesting, item.app_group.lxc_config.nesting)
      fuse    = coalesce(item.node_override.lxc_config.fuse, item.app_group.lxc_config.fuse)
      keyctl  = coalesce(item.node_override.lxc_config.keyctl, item.app_group.lxc_config.keyctl)

      cpu_cores   = coalesce(item.node_override.lxc_config.cpu_cores, item.app_group.lxc_config.cpu_cores)
      memory_size = coalesce(item.node_override.lxc_config.memory_size, item.app_group.lxc_config.memory_size)

      disk_datastore_id = coalesce(item.node_override.lxc_config.disk_datastore_id, item.app_group.lxc_config.disk_datastore_id, var.target_datastore)
      os_type           = coalesce(item.node_override.lxc_config.os_type, item.app_group.lxc_config.os_type)
      disk_size         = coalesce(item.node_override.lxc_config.disk_size, item.app_group.lxc_config.disk_size)

      vlan_bridge = coalesce(item.node_override.lxc_config.vlan_bridge, item.app_group.lxc_config.vlan_bridge)
      vlan_id     = coalesce(item.node_override.lxc_config.vlan_id, item.app_group.lxc_config.vlan_id)

      ipv4_address = item.node_override.lxc_config.ipv4_address
      ipv4_gateway = coalesce(item.node_override.lxc_config.ipv4_gateway, item.app_group.lxc_config.ipv4_gateway, "192.168.0.1")

      user_account_password = (
        (var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")] != null &&
          var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].password != null &&
        trimspace(var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].password) != "") ?
        var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].password :
        "ERROR: 'password' not found for LXC '${item.node_key}'. Check secret '${coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")}' in 'user_credentials'." [999]
      )
      user_account_keys = (
        (var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")] != null &&
          var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].ssh_public_keys != null &&
        var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].ssh_public_keys != []) ?
        var.user_credentials[coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")].ssh_public_keys :
        "ERROR: 'ssh_public_keys' not found for LXC '${item.node_key}'. Check secret '${coalesce(item.node_override.cloud_init_user, item.app_group.cloud_init_user, "default_user")}' in 'user_credentials'." [999]
      )
    }
    if coalesce(item.node_override.enabled, item.app_group.enabled) && item.app_group.type == "lxc"
  }
}
