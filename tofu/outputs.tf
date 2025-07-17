# -----------------------------------------------------------------------------
# QEMU VM DETAILS OUTPUT
#
# This output provides a detailed, machine-readable map of all QEMU VMs
# that were successfully created by this apply.
# -----------------------------------------------------------------------------

output "qemu_vm_details" {
  description = "A detailed map of all created QEMU virtual machines, grouped by their resource group."
  value = {
    for group_key, module_instance in module.qemu_groups :
    group_key => module_instance.vm_details
  }
}


# -----------------------------------------------------------------------------
# LXC CONTAINER DETAILS OUTPUT
#
# This output provides a detailed, machine-readable map of all LXC
# containers that were successfully created by this apply.
# -----------------------------------------------------------------------------

output "lxc_container_details" {
  description = "A detailed map of all created LXC containers, grouped by their resource group."
  value = {
    for group_key, module_instance in module.lxc_groups :
    group_key => module_instance.container_details
  }
}


# -----------------------------------------------------------------------------
# ACTIVE INFRASTRUCTURE SUMMARY
#
# This output provides a clean, human-readable summary of the running
# infrastructure, grouped by the original resource group names. It is
# perfect for a quick overview of what is active and their IP addresses.
# -----------------------------------------------------------------------------

output "active_infrastructure_summary" {
  description = "A high-level summary of active infrastructure, grouped by resource group, showing each node's IP address."
  value = merge(
      {
      # Loop through the original resource groups defined in the .tfvars file...
      for group_key, module_instance in module.qemu_groups :
      # ...and create a top-level key for the group name (e.g., "laboon_cluster").
      group_key => {
        # Then, loop through the nodes defined within that group...
        for vm_name, details in module_instance.vm_details :
        # ...and create a key for the node's hostname (e.g., "laboon-1").
        vm_name => details.ip_address
      }
    },
    {
      for group_key, module_instance in module.lxc_groups :
      group_key => {
        for container_name, details in module_instance.container_details :
        container_name => details.ip_address
      }
    }
  )
}