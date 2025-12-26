resource "proxmox_virtual_environment_container" "module_lxc" {
  # --- General Settings ---
  node_name     = var.node_name
  vm_id         = var.vm_id
  description   = var.description
  tags          = var.tags
  start_on_boot = var.on_boot
  started       = var.started
  unprivileged  = var.unprivileged

  features {
    nesting = var.nesting
    # Need root user. So turned off from GitOps
    # fuse    = var.fuse
    # keyctl  = var.keyctl
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
