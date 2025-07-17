# -----------------------------------------------------------------------------
# LOCALS BLOCK
#
# This block filters the main 'resource_groups' variable into separate maps
# for QEMU and LXC groups, which makes calling the modules cleaner.
# -----------------------------------------------------------------------------

locals {
  # Create a map of only the QEMU resource groups.
  qemu_resource_groups = {
    for key, group in var.resource_groups : key => group
    if group.enabled && group.type == "qemu"
  }

  # Create a map of only the LXC resource groups.
  lxc_resource_groups = {
    for key, group in var.resource_groups : key => group
    if group.enabled && group.type == "lxc"
  }
}

# -----------------------------------------------------------------------------
# MODULE CALLS
#
# This single module block is responsible for creating ALL QEMU VM.
# -----------------------------------------------------------------------------

module "qemu_groups" {
  # Use for_each to call our QEMU module for every enabled QEMU group.
  for_each = local.qemu_resource_groups

  # --- Module Inputs ---
  source = "./modules/proxmox_qemu_vm"

  group_data       = each.value
  hardware_profile = var.hardware_profiles.qemu[each.value.hardware_profile_key]
  target_node      = var.resource_defaults.target_node
  storage_pool     = var.resource_defaults.storage_pool
  network_bridge   = var.resource_defaults.network_bridge
  gateway          = var.network_defaults.gateway
  cidr_mask        = var.network_defaults.cidr_mask
  user_profile     = var.user_profile
  user_credentials = var.user_credentials
}


# -----------------------------------------------------------------------------
# LXC CONTAINER CREATION
#
# This single module block is responsible for creating ALL LXC containers.
# -----------------------------------------------------------------------------

module "lxc_groups" {
  for_each = local.lxc_resource_groups

  # --- Module Inputs ---
  source = "./modules/proxmox_lxc_container"

  group_data       = each.value
  hardware_profile = var.hardware_profiles.lxc[each.value.hardware_profile_key]
  target_node      = var.resource_defaults.target_node
  storage_pool     = var.resource_defaults.storage_pool
  network_bridge   = var.resource_defaults.network_bridge
  gateway          = var.network_defaults.gateway
  cidr_mask        = var.network_defaults.cidr_mask
  user_credentials = var.user_credentials
}