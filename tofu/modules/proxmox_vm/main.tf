resource "proxmox_virtual_environment_vm" "module_vm" {
  # General and OS Settings
  node_name   = var.node_name
  vm_id       = var.vm_id
  name        = var.name
  description = var.description
  tags        = var.tags
  on_boot     = var.on_boot
  started     = var.started
  boot_order  = ["scsi0", "net0"]


  # OS and Boot Configuration
  operating_system {
    type = "l26"
  }

  # System and QEMU Agent
  machine = "q35"
  bios    = "ovmf"
  efi_disk {
    datastore_id      = var.disk_datastore_id
    pre_enrolled_keys = true
  }
  scsi_hardware = "virtio-scsi-pci"
  agent {
    enabled = true
  }

  # Disk Configuration
  disk {
    interface    = "scsi0"
    datastore_id = var.disk_datastore_id
    import_from  = var.source_image_path
    size         = var.disk_size
    cache        = "writeback"
    discard      = "on"
    ssd          = var.disk_ssd
  }

  # CPU Configuration
  cpu {
    cores   = var.cpu_cores
    sockets = var.cpu_sockets
    type    = "host"
  }

  # Memory Configuration
  memory {
    dedicated = var.memory
    floating  = var.memory
  }

  # Network Configuration
  network_device {
    bridge   = var.vlan_bridge
    vlan_id  = var.vlan_id
    firewall = false
    model    = "virtio"
  }

  # Serial and VGA Configuration for Console Access
  serial_device {}
  vga {
    type = "serial0"
  }

  # Cloud-Init Configuration (as top-level arguments)
  initialization {
    datastore_id = var.disk_datastore_id
    interface    = "ide0"

    ip_config {
      ipv4 {
        address = var.ipv4_address
        gateway = var.ipv4_gateway
      }
      ipv6 {
        address = "dhcp"
      }
    }

    user_account {
      username = var.user_account_username
      password = var.user_account_password
      keys     = var.user_account_keys
    }
  }

  # This block tells OpenTofu to ignore changes to the 'import_from'
  # attribute after the VM has been created.
  lifecycle {
    ignore_changes = [
      disk[0].import_from,
    ]
  }
}


# resource "proxmox_virtual_environment_vm" "module_vm" {
#   # --- General and OS Settings ---
#   node_name   = "moo-moo"
#   vm_id       = 500
#   name        = "web-server-01"
#   description = "Primary web server, managed by OpenTofu. Ubuntu 24.04."
#   tags        = ["managed-by-tofu", "web", "ubuntu"]
#   on_boot     = false
#   started     = false
#   boot_order  = ["scsi0", "net0"]


#   # --- OS and Boot Configuration ---
#   operating_system {
#     type = "l26"
#   }

#   # --- System and QEMU Agent ---
#   machine = "q35"
#   bios    = "ovmf"
#   efi_disk {
#     datastore_id      = "local-thin"
#     pre_enrolled_keys = true
#   }
#   scsi_hardware = "virtio-scsi-pci"
#   agent {
#     enabled = true
#   }

#   # --- Disk Configuration ---
#   disk {
#     interface    = "scsi0"
#     datastore_id = "local-thin"
#     import_from  = proxmox_virtual_environment_file.ubuntu_custom_image.id
#     size         = 10
#     cache        = "writeback"
#     discard      = "on"
#     ssd          = true
#   }

#   # --- CPU Configuration ---
#   cpu {
#     cores   = 2
#     sockets = 1
#     type    = "host"
#   }

#   # --- Memory Configuration ---
#   memory {
#     dedicated = 2048
#     floating  = 2048
#   }

#   # --- Network Configuration ---
#   network_device {
#     bridge   = "vmbr0"
#     vlan_id  = 1
#     firewall = true
#     model    = "virtio"
#   }

#   # --- Serial and VGA Configuration for Console Access ---
#   serial_device {}
#   vga {
#     type = "serial0"
#   }

#   # --- Cloud-Init Configuration (as top-level arguments) ---
#   initialization {
#     datastore_id = "local-thin"
#     interface    = "ide0"

#     ip_config {
#       ipv4 {
#         address = "dhcp"
#       }
#     }

#     user_account {
#       keys     = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDwC01G8nJScuxp7Cga8uUsnHUW2IpXXiiTw1gzhEL4P RyzenWindows"]
#       password = "devdevdev"
#       username = "dev"
#     }
#   }

#   # This block tells OpenTofu to ignore changes to the 'import_from'
#   # attribute after the VM has been created.
#   lifecycle {
#     ignore_changes = [
#       disk[0].import_from,
#     ]
#   }
# }
