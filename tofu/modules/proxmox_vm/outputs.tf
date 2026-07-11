# -----------------------------------------------------------------------------
# MODULE OUTPUTS
# -----------------------------------------------------------------------------
# This file defines the data that the module will return after creating a VM.
# -----------------------------------------------------------------------------

output "vm_details" {
  description = "Filtered attributes of the created Proxmox VM resource to avoid deprecated warnings."
  value = {
    id             = proxmox_virtual_environment_vm.module_vm.id
    name           = proxmox_virtual_environment_vm.module_vm.name
    node_name      = proxmox_virtual_environment_vm.module_vm.node_name
    tags           = proxmox_virtual_environment_vm.module_vm.tags
    ipv4_addresses = proxmox_virtual_environment_vm.module_vm.ipv4_addresses
    initialization = proxmox_virtual_environment_vm.module_vm.initialization
    app_key        = var.app_key
    ansible_groups = var.ansible_groups
  }
}
