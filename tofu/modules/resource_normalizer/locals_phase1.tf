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
