# -----------------------------------------------------------------------------
# MODULE OUTPUTS
# -----------------------------------------------------------------------------
# This file defines the data that the module will return after creating a LXC.
# -----------------------------------------------------------------------------

output "lxc_details" {
  description = "Filtered attributes of the created Proxmox LXC resource to avoid deprecated warnings."
  value = {
    id        = proxmox_virtual_environment_container.module_lxc.id
    node_name = proxmox_virtual_environment_container.module_lxc.node_name
    tags      = proxmox_virtual_environment_container.module_lxc.tags
    app_key   = var.app_key
  }
}
