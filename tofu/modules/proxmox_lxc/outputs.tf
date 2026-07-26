# -----------------------------------------------------------------------------
# MODULE OUTPUTS
# -----------------------------------------------------------------------------
# This file defines the data that the module will return after creating a LXC.
# -----------------------------------------------------------------------------

output "lxc_details" {
  description = "Filtered attributes of the created Proxmox LXC resource to avoid deprecated warnings."
  value = {
    id             = proxmox_virtual_environment_container.module_lxc.id
    name           = var.hostname
    node_name      = proxmox_virtual_environment_container.module_lxc.node_name
    tags           = proxmox_virtual_environment_container.module_lxc.tags
    # TODO: Support multiple IPv4 addresses/interfaces in the future
    ipv4_addresses = [try(split("/", var.ipv4_address)[0], var.ipv4_address)]
    initialization = proxmox_virtual_environment_container.module_lxc.initialization
    app_key        = var.app_key
    ansible_groups = var.ansible_groups
  }
}
