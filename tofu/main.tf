# -----------------------------------------------------------------------------
# LOCALS BLOCK
#
# This block is the "brain" of our configuration. It processes the complex
# 'resource_groups' variable and flattens it into two simple, filtered lists:
# 1. qemu_nodes: A flat map of all QEMU VMs that should be created.
# 2. lxc_nodes: A flat map of all LXC containers that should be created.
#
# This pattern allows us to use a clean 'for_each' in our resource blocks
# and avoids duplicating code.
# -----------------------------------------------------------------------------

locals {
  # --- Step 1: Flatten the nested data into a single, simple list ---
  # We create a list where each element is an object containing all the
  # combined information for a single node (from the group and the node itself).
  all_nodes_list = flatten([
    # Loop through each resource group (e.g., "laboon_cluster")...
    for group_name, group_data in var.resource_groups : [
      # ...then loop through each node within that group (e.g., "laboon-1").
      for node_name, node_data in group_data.nodes : {
        # Combine all the relevant data into a single object.
        group_name           = group_name
        hostname             = node_name
        enabled              = group_data.enabled
        type                 = group_data.type
        template             = group_data.template
        hardware_profile_key = group_data.hardware_profile_key
        tags                 = group_data.tags
        id                   = node_data.id
        ip                   = node_data.ip
      }
    ]
  ])

  # --- Step 2: Create a filtered map for all QEMU nodes ---
  qemu_nodes = {
    for node in local.all_nodes_list :
    "${node.group_name}/${node.hostname}" => merge(
      node,
      var.hardware_profiles.qemu[node.hardware_profile_key]
    )
    if node.enabled && node.type == "qemu"
  }

  # --- Step 3: Create a filtered map for all LXC nodes ---
  lxc_nodes = {
    for node in local.all_nodes_list :
    "${node.group_name}/${node.hostname}" => merge(
      node,
      var.hardware_profiles.lxc[node.hardware_profile_key]
    )
    if node.enabled && node.type == "lxc"
  }
}


# -----------------------------------------------------------------------------
# QEMU VIRTUAL MACHINE CREATION
#
# This single resource block is responsible for creating ALL QEMU VMs.
# It iterates over the 'local.qemu_nodes' map we created above.
# -----------------------------------------------------------------------------

resource "proxmox_vm_qemu" "qemu_servers" {
  # The for_each loop iterates over our flattened map of QEMU nodes.
  for_each = local.qemu_nodes

  # --- VM Identification and Placement ---
  vmid        = each.value.id
  name        = each.value.hostname
  tags        = join(",", each.value.tags) # The provider expects a comma-separated string
  target_node = var.resource_defaults.target_node
  clone       = each.value.template
  full_clone  = true
  onboot      = false
  vm_state    = "stopped"

  # --- Hardware Configuration ---
  bios   = "ovmf"
  scsihw = "virtio-scsi-single"
  agent  = 1
  memory = each.value.memory
  cpu {
    cores = each.value.cores
    type  = "host"
  }

  disks {
    ide {
      ide1 {
        cloudinit {
          storage = var.resource_defaults.storage_pool
        }
      }
    }
    virtio {
      virtio0 {
        disk {
          size     = each.value.disk_size
          storage  = var.resource_defaults.storage_pool
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
    bridge   = var.resource_defaults.network_bridge
    firewall = false # Set to true if you have configured the PVE firewall
  }

  serial {
    id   = 0
    type = "socket"
  }

  # --- Cloud-Init Configuration ---
  os_type   = "cloud-init"
  ipconfig0 = "ip=${each.value.ip}/${var.network_defaults.cidr_mask},gw=${var.network_defaults.gateway}"

  ciuser     = var.user_profile.username
  cipassword = var.user_credentials.password
  ciupgrade  = var.user_profile.package_upgrade
  # The 'join' function correctly formats the list of keys into the multi-line
  # string format that the provider expects, without needing <<EOF.
  sshkeys = join("\n", var.user_credentials.ssh_public_keys)
}


# -----------------------------------------------------------------------------
# LXC CONTAINER CREATION
#
# This single resource block is responsible for creating ALL LXC containers.
# It iterates over the 'local.lxc_nodes' map.
# -----------------------------------------------------------------------------

resource "proxmox_lxc" "lxc_servers" {
  for_each = local.lxc_nodes

  # --- Container Identification and Placement ---
  vmid     = each.value.id
  hostname = each.value.hostname
  tags     = join(",", each.value.tags)

  target_node = var.resource_defaults.target_node
  ostemplate  = each.value.template

  # --- Hardware Configuration ---
  cores  = each.value.cores
  memory = each.value.memory
  rootfs {
    storage = var.resource_defaults.storage_pool
    size    = each.value.rootfs_size
  }

  # --- Network Configuration ---
  network {
    name   = "eth0"
    bridge = var.resource_defaults.network_bridge
    ip     = "${each.value.ip}/${var.network_defaults.cidr_mask}"
    gw     = var.network_defaults.gateway
  }

  # --- Cloud-Init / OS Configuration ---
  onboot         = false
  unprivileged   = true
  start          = true
  ssh_public_keys = join("\n", var.user_credentials.ssh_public_keys)
}
