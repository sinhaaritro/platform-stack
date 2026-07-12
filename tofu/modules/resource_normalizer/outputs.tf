# -----------------------------------------------------------------------------
# MODULE OUTPUTS - RESOURCE NORMALIZER MODULE
# -----------------------------------------------------------------------------

output "final_vm_list" {
  description = "Flat map of enabled VMs, keyed by node name. Ready for for_each on proxmox_vm module."
  value       = local.final_vm_list
}

output "final_lxc_list" {
  description = "Flat map of enabled LXCs, keyed by node name. Ready for for_each on proxmox_lxc module."
  value       = local.final_lxc_list
}

output "requested_os_images" {
  description = "Deduplicated map of OS images needed by the VMs. Keyed by 'os_type-os_version'."
  value       = local.requested_os_images
}

output "debug_info" {
  description = "All intermediate normalization data for diagnostic output."
  value = var.enable_debug ? nonsensitive({
    normalized_resources = local.normalized_resources
    vm_groups            = local._vm_groups
    lxc_groups           = local._lxc_groups
    flattened_vms        = local._flattened_vms
    flattened_lxcs       = local._flattened_lxcs
    final_vm_list        = local.final_vm_list
    final_lxc_list       = local.final_lxc_list
  }) : null
}
