# -----------------------------------------------------------------------------
# QEMU VM DETAILS OUTPUT
#
# This output provides a detailed, machine-readable map of all QEMU VMs
# that were successfully created by this apply.
# -----------------------------------------------------------------------------

output "qemu_vm_details" {
  description = "A detailed map of all created QEMU virtual machines, keyed by their unique resource identifier."
  value = {
    # Loop over the created QEMU resources...
    for key, vm in proxmox_vm_qemu.qemu_servers :
    # ...using the same unique key as the 'for_each'...
    key => {
      # ...to build an object with the most useful information.
      hostname     = vm.name
      vmid         = vm.vmid
      # Extract just the IP address from the 'ipconfig0' string.
      ip_address   = regex("ip=([\\d\\.]+)/", vm.ipconfig0)[0]
      default_user = var.user_profile.username
      # Convert the comma-separated tags string back into a list.
      tags         = split(",", vm.tags)
    }
  }
}


# -----------------------------------------------------------------------------
# LXC CONTAINER DETAILS OUTPUT
#
# This output provides a detailed, machine-readable map of all LXC
# containers that were successfully created by this apply.
# -----------------------------------------------------------------------------

output "lxc_container_details" {
  description = "A detailed map of all created LXC containers, keyed by their unique resource identifier."
  value = {
    # Loop over the created LXC resources...
    for key, container in proxmox_lxc.lxc_servers :
    # ...using the same unique key as the 'for_each'...
    key => {
      # ...to build an object with the most useful information.
      hostname     = container.hostname
      vmid         = container.vmid
      # Extract just the IP address from the 'network.ip' CIDR string.
      ip_address   = split("/", container.network[0].ip)[0]
      default_user = var.user_profile.username
      tags         = split(",", container.tags)
    }
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
  value = {
    # Loop through the original resource groups defined in the .tfvars file...
    for group_name, group_data in var.resource_groups :
    # ...and create a top-level key for the group name (e.g., "laboon_cluster").
    group_name => {
      # Then, loop through the nodes defined within that group...
      for node_name, node_data in group_data.nodes :
      # ...and create a key for the node's hostname (e.g., "laboon-1").
      node_name => (
        # Use a conditional (ternary) operator to decide which resource map to query.
        group_data.type == "qemu" ?
        # If it's a QEMU VM, look up the resource using its unique key and extract the IP.
        regex("ip=([\\d\\.]+)/", proxmox_vm_qemu.qemu_servers["${group_name}/${node_name}"].ipconfig0)[0] :
        # Otherwise (it's an LXC), look up the resource and extract its IP.
        split("/", proxmox_lxc.lxc_servers["${group_name}/${node_name}"].network[0].ip)[0]
      )
    }
    # ...but only include the entire group in the final output if it was enabled.
    if group_data.enabled
  }
}