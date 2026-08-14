resource "proxmox_virtual_environment_container" "module_lxc" {
  # --- General Settings ---
  node_name     = var.node_name
  vm_id         = var.vm_id
  description   = var.description
  tags          = var.tags
  start_on_boot = var.on_boot
  started       = var.started
  unprivileged  = var.unprivileged

  # Feature flags may only be changed by root@pam on privileged containers,
  # so they are only sent for unprivileged ones (privileged get Proxmox defaults).
  dynamic "features" {
    for_each = var.unprivileged ? [1] : []
    content {
      nesting = var.nesting
      # Need root user. So turned off from GitOps
      # fuse    = var.fuse
      # keyctl  = var.keyctl
    }
  }

  # --- OS Template ---
  operating_system {
    template_file_id = var.template_file_id
    type             = var.os_type
  }

  # --- Disk Configuration ---
  disk {
    datastore_id = var.disk_datastore_id
    size         = var.disk_size
  }

  dynamic "mount_point" {
    for_each = var.mount_points
    content {
      path          = mount_point.value.path
      volume        = mount_point.value.volume
      size          = mount_point.value.size
      mount_options = mount_point.value.mount_options
      read_only     = mount_point.value.read_only
      backup        = mount_point.value.backup
      quota         = mount_point.value.quota
      acl           = mount_point.value.acl
      replicate     = mount_point.value.replicate
    }
  }

  # --- Hardware Resources ---
  cpu {
    cores = var.cpu_cores
  }
  memory {
    dedicated = var.memory
  }

  # --- Network Configuration ---
  network_interface {
    name    = "net0"
    bridge  = var.vlan_bridge
    vlan_id = var.vlan_id
  }

  # --- THIS IS THE CORRECT INITIALIZATION BLOCK ---
  initialization {
    hostname = var.hostname
    ip_config {
      ipv4 {
        address = var.ipv4_address
        gateway = var.ipv4_gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      password = var.user_account_password
      keys     = var.user_account_keys
    }
  }
  # ----------------------------------------------

  # --- Lifecycle Management ---
  # lifecycle {
  #   prevent_destroy = true
  # }
}
