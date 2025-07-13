# This single resource block will create all three VMs
# by looping over the 'laboon_vms' variable.
resource "proxmox_vm_qemu" "laboon_server" {
  # The 'for_each' meta-argument is what enables the loop.
  for_each = var.laboon_cluster_enabled ? var.laboon_vms : {}

  # VM Identification and Placement
  vmid = each.value.vmid
  name = each.key
  tags = "laboon"

  target_node = var.target_node
  clone       = var.template_name
  full_clone  = true

  # Hardware Configuration
  bios      = "ovmf"
  scsihw    = "virtio-scsi-single"
  agent     = 1                       # Enable the QEMU Guest Agent
  onboot    = false                   # Start the VM on creation
  vm_state  = "stopped"


  # VM Resources
  memory    = var.vm_memory
  # balloon   = 1
  cpu {
    cores   = var.vm_cores
    type    = "host"
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
          size      = var.vm_disk_size
          storage   = var.storage_pool
          discard   = true
          backup    = true
          iothread  = true
        }
      }
    }
  }
  boot = "order=virtio0;net0"

  # VM Network Configuration
  network {
    id       = 0
    model    = "virtio"
    bridge   = var.network_bridge
    firewall = true
  }

  # Cloud-Init Configuration
  os_type = "cloud-init"              # This configures the VM's OS on first boot.
  
  ciuser      = var.cloud_init_user.username
  cipassword  = var.cloud_init_user.password
  ciupgrade   = var.cloud_init_user.upgrade
  sshkeys     = var.cloud_init_user.ssh_key

  serial {
    id    = 0
    type  = "socket"
  }

  # Build the IP address string dynamically from our variables.
  ipconfig0 = "ip=${each.value.ip}/${var.cidr_mask},gw=${var.gateway_ip}"

  # This section creates a user and adds your SSH key for passwordless access.
  # cicustom = "user=local:snippets/user-data.yaml"
}

# # Cloud-Init User Data
# # This defines the user configuration for Cloud-Init.
# # It's better to manage this as a separate local file for clarity.
# resource "local_file" "user_data" {
#   # for_each is needed here as well to create a separate user-data
#   # file for each VM, which can be useful for customization.
#   for_each = var.laboon_vms

#   filename = "${path.module}/snippets/user-data.yaml"
#   content = templatefile("${path.module}/templates/cloud_init.tftpl", {
#     hostname          = each.key
#     ssh_public_key    = var.ssh_public_key
#   })
# }

# # This directory ensures the snippet path exists.
# resource "local_file" "snippets_dir" {
#   filename = "${path.module}/snippets/.placeholder"
#   content  = ""
# }

# resource "local_file" "templates_dir" {
#   filename = "${path.module}/templates/.placeholder"
#   content  = ""
# }