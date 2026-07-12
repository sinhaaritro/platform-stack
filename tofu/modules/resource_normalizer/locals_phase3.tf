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

      # OS Details
      os_type    = try(item.node_override.vm_config.os_type, item.app_group.vm_config.os_type, var.default_os_type)
      os_version = coalesce(item.node_override.vm_config.os_version, item.app_group.vm_config.os_version, var.default_os_version)

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
      template_file_id  = coalesce(item.node_override.lxc_config.template_file_id, item.app_group.lxc_config.template_file_id)
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

  # Scan final_vm_list for unique OS type + version combinations
  requested_os_images = {
    for key, val in {
      for vm_key, vm in local.final_vm_list :
      "${vm.os_type}-${vm.os_version}" => {
        os_type    = vm.os_type
        os_version = vm.os_version
      }...
    } : key => val[0]  # Deduplicate — take first occurrence
  }
}
