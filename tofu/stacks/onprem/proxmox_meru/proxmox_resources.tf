# -----------------------------------------------------------------------------
# STEP 6: CREATE VIRTUAL MACHINES 
# -----------------------------------------------------------------------------
# This block iterates over our final, flattened map of VMs and calls the
# 'proxmox_vm' module for each one, passing in its fully resolved configuration.
# -----------------------------------------------------------------------------
module "proxmox_vms" {
  source   = "../../../modules/proxmox_vm"
  for_each = local.final_vm_list

  depends_on = [proxmox_virtual_environment_file.custom_image_upload]

  # Main info
  vm_id          = each.value.vm_id
  name           = each.value.name
  app_key        = each.value.app_key
  node_name      = each.value.node_name
  description    = each.value.description
  tags           = each.value.tags
  on_boot        = each.value.on_boot
  started        = each.value.started
  ansible_groups = each.value.ansible_groups

  # Hardware
  cpu_cores   = each.value.cpu_cores
  cpu_sockets = each.value.cpu_sockets
  memory      = each.value.memory_size

  # Disk
  disk_datastore_id = each.value.disk_datastore_id
  disk_size         = each.value.disk_size
  disk_ssd          = each.value.disk_ssd
  source_image_path = local.final_image_paths[each.value.os_version]


  # Network
  vlan_bridge = each.value.vlan_bridge
  vlan_id     = each.value.vlan_id

  # Cloud-Init
  ipv4_address          = each.value.ipv4_address
  ipv4_gateway          = each.value.ipv4_gateway
  user_account_username = each.value.user_account_username
  user_account_password = each.value.user_account_password
  user_account_keys     = each.value.user_account_keys

  # Aditional Disks
  additional_disks = each.value.additional_disks
}

# -----------------------------------------------------------------------------
# STEP 7: CREATE CONTAINERS (LXC)
# -----------------------------------------------------------------------------
# This is where you would add a similar 'module "lxc_containers"' block.
# It would iterate over 'local.lxc_groups' and call a new 'proxmox_lxc' module.
# -----------------------------------------------------------------------------
module "module_lxc" {
  source   = "../../../modules/proxmox_lxc"
  for_each = local.final_lxc_list

  depends_on = [proxmox_virtual_environment_file.custom_image_upload]

  # Main info
  vm_id       = each.value.vm_id
  app_key     = each.value.app_key
  node_name   = each.value.node_name
  description = each.value.description
  tags        = each.value.tags
  on_boot     = each.value.on_boot
  started     = each.value.started

  unprivileged = each.value.unprivileged

  # Features 
  nesting = true
  fuse    = true
  keyctl  = true

  # --- OS Template ---
  template_file_id = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
  os_type          = "debian"

  # Hardware
  cpu_cores = each.value.cpu_cores
  memory    = each.value.memory_size

  # Disk
  disk_datastore_id = each.value.disk_datastore_id
  disk_size         = each.value.disk_size

  # Network
  vlan_bridge = each.value.vlan_bridge
  vlan_id     = each.value.vlan_id

  # Cloud-Init
  hostname              = each.value.name
  ipv4_address          = each.value.ipv4_address
  ipv4_gateway          = each.value.ipv4_gateway
  user_account_password = each.value.user_account_password
  user_account_keys     = each.value.user_account_keys
}
