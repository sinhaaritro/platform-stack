# It creates a set of containers based on the 'nodes' map passed into the module.
resource "proxmox_lxc" "server" {
  for_each = var.group_data.nodes

  # --- Container Identification and Placement ---
  vmid     = each.value.id
  hostname = each.key
  tags     = join(",", var.group_data.tags)

  target_node = var.target_node
  ostemplate  = var.group_data.template

  # --- Hardware Configuration ---
  cores  = var.hardware_profile.cores
  memory = var.hardware_profile.memory
  rootfs {
    storage = var.storage_pool
    size    = var.hardware_profile.rootfs_size
  }

  # --- Network Configuration ---
  network {
    name   = "eth0"
    bridge = var.network_bridge
    ip     = "${each.value.ip}/${var.cidr_mask}"
    gw     = var.gateway
  }

  # --- Cloud-Init / OS Configuration ---
  onboot         = false
  unprivileged   = true
  start          = true
  ssh_public_keys = join("\n", var.user_credentials.ssh_public_keys)
}