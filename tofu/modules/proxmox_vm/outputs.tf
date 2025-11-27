# -----------------------------------------------------------------------------
# MODULE OUTPUTS
# -----------------------------------------------------------------------------
# This file defines the data that the module will return after creating a VM.
# -----------------------------------------------------------------------------

output "vm_details" {
  description = "A complete object containing all attributes of the created Proxmox VM resource."
  # By outputting the entire resource, we give the calling module full access
  # to all computed values like IP/MAC addresses, final disk paths, etc.
  value = merge(proxmox_virtual_environment_vm.module_vm,
    {
      "app_key" = var.app_key
    }
  )
}
