# It creates a set of VMs based on the 'nodes' map passed into the module.
resource "proxmox_vm_qemu" "server" {
  for_each = var.group_data.nodes

  # --- VM Identification and Placement ---
  vmid        = each.value.id
  name        = each.key
  tags        = join(",", var.group_data.tags)
  target_node = var.target_node
  clone       = var.group_data.template
  full_clone  = true
  onboot      = false
  vm_state    = "stopped"

  # --- Hardware Configuration ---
  bios   = "ovmf"
  scsihw = "virtio-scsi-single"
  agent  = 1
  memory = var.hardware_profile.memory
  cpu {
    cores = var.hardware_profile.cores
    type  = "host"
  }
  disks {
    ide { 
        ide1 { 
            cloudinit { 
                storage = var.storage_pool 
            } 
        } 
    }
    virtio {
      virtio0 {
        disk {
          size     = var.hardware_profile.disk_size
          storage  = var.storage_pool
          discard  = true
          backup   = true
          iothread = true
        }
      }
    }
  }
  boot = "order=virtio0;net0"
  
  network {
    id       = 0
    model    = "virtio"
    bridge   = var.network_bridge
    firewall = false
  }
  
  serial {
    id   = 0
    type = "socket"
  }

  # --- Cloud-Init Configuration ---
  os_type   = "cloud-init"
  ipconfig0 = "ip=${each.value.ip}/${var.cidr_mask},gw=${var.gateway}"

  ciuser     = var.user_profile.username
  cipassword = var.user_credentials.password
  ciupgrade  = var.user_profile.package_upgrade
  # The 'join' function correctly formats the list of keys into the multi-line
  # string format that the provider expects, without needing <<EOF.
  sshkeys    = join("\n", var.user_credentials.ssh_public_keys)
}