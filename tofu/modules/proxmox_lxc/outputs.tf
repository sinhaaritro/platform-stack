# -----------------------------------------------------------------------------
# MODULE OUTPUTS
# -----------------------------------------------------------------------------
# This file defines the data that the module will return after creating a LXC.
# -----------------------------------------------------------------------------

output "lxc_details" {
  description = "A complete object containing all attributes of the created Proxmox LXC resource."
  # By outputting the entire resource, we give the calling module full access
  # to all computed values like IP/MAC addresses, final disk paths, etc.
  value = merge(proxmox_virtual_environment_container.module_lxc,
    {
      "app_key" = var.app_key
    }
  )
}
